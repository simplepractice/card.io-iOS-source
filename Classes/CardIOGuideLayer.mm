//
//  CardGuideOverlayView.m
//  See the file "LICENSE.md" for the full license governing this code.
//

#if USE_CAMERA || SIMULATE_CAMERA

#import "CardIOGuideLayer.h"
#import "CardIOViewController.h"
#import "CardIOCGGeometry.h"
#import "CardIOVideoFrame.h"
#import "CardIODmzBridge.h"
#import "CardIOMacros.h"
#import "CardIOAnimation.h"
#import "CardIOOrientation.h"
#import "CardIOCGGeometry.h"

#pragma mark - Colors

#define kStandardMinimumBoundsWidth 300.0f
#define kStandardLineWidth 12.0f
#define kStandardCornerSize 50.0f
#define kAdjustFudge 0.2f  // Because without this, we see a mini gap between edge path and corner path.

#define kEdgeDecay 0.5f
#define kEdgeOnThreshold 0.7f
#define kEdgeOffThreshold 0.3f

#define kAllEdgesFoundScoreDecay 0.5f
#define kNumEdgesFoundScoreDecay 0.5f
#define kStrokeLayerName @"strokeLayer"

#pragma mark - Types

typedef enum { 
  kTopLeft,
  kTopRight,
  kBottomLeft,
  kBottomRight,
} CornerPositionType;

#pragma mark - Interface

@interface CardIOGuideLayer ()

@property(nonatomic, weak, readwrite) id<CardIOGuideLayerDelegate> guideLayerDelegate;
@property(nonatomic, strong, readwrite) CAShapeLayer *backgroundOverlay;
@property(nonatomic, assign, readwrite) float edgeScoreTop;
@property(nonatomic, assign, readwrite) float edgeScoreRight;
@property(nonatomic, assign, readwrite) float edgeScoreBottom;
@property(nonatomic, assign, readwrite) float edgeScoreLeft;
@property(nonatomic, assign, readwrite) float allEdgesFoundDecayedScore;
@property(nonatomic, assign, readwrite) float numEdgesFoundDecayedScore;

#if CARDIO_DEBUG
@property(nonatomic, strong, readwrite) CALayer *debugOverlay;
#endif
@end


#pragma mark - Implementation

@implementation CardIOGuideLayer

- (id)initWithDelegate:(id<CardIOGuideLayerDelegate>)guideLayerDelegate {
  if((self = [super init])) {
    _guideLayerDelegate = guideLayerDelegate;
    
    _deviceOrientation = UIDeviceOrientationPortrait;

    _edgeScoreTop = 0.0f;
    _edgeScoreRight = 0.0f;
    _edgeScoreBottom = 0.0f;
    _edgeScoreLeft = 0.0f;

    _allEdgesFoundDecayedScore = 0.0f;
    _numEdgesFoundDecayedScore = 0.0f;

    _backgroundOverlay = [CAShapeLayer layer];
    _backgroundOverlay.fillColor = [UIColor colorWithWhite:0 alpha:0.5f].CGColor;

    CAShapeLayer *strokeLayer = [CAShapeLayer layer];
    strokeLayer.name = kStrokeLayerName;
    strokeLayer.frame = self.bounds;
    strokeLayer.lineWidth = 1;
    strokeLayer.fillColor = UIColor.clearColor.CGColor;
    strokeLayer.strokeColor = UIColor.whiteColor.CGColor;
    [_backgroundOverlay addSublayer:strokeLayer];

    [self addSublayer:_backgroundOverlay];

#if CARDIO_DEBUG
    _debugOverlay = [CALayer layer];
    _debugOverlay.cornerRadius = 0.0f;
    _debugOverlay.masksToBounds = YES;
    _debugOverlay.borderWidth = 0.0f;
    [self addSublayer:_debugOverlay];
#endif
    
    // setting the capture frame here serves to initialize the remaining shapelayer properties
    _videoFrame = nil;

    [self setNeedsLayout];
  }
  return self;
}

+ (CGPathRef)newPathFromPoint:(CGPoint)firstPoint toPoint:(CGPoint)secondPoint {
  CGMutablePathRef path = CGPathCreateMutable();
  CGPathMoveToPoint(path, NULL, firstPoint.x, firstPoint.y);
  CGPathAddLineToPoint(path, NULL, secondPoint.x, secondPoint.y);
  return path;
}

+ (CGPathRef)newCornerPathFromPoint:(CGPoint)point size:(CGFloat)size positionType:(CornerPositionType)posType {
#if __LP64__
  size = fabs(size);
#else
  size = fabsf(size);
#endif
  CGMutablePathRef path = CGPathCreateMutable();
  CGPoint pStart = point, 
          pEnd = point;
  
  // All this assumes phone is turned horizontally, to widescreen mode
  switch (posType) {
    case kTopLeft:
      pStart.x -= size;
      pEnd.y += size;
      break;
    case kTopRight:
      pStart.x -= size;
      pEnd.y -= size;
      break;
    case kBottomLeft:
      pStart.x += size;
      pEnd.y += size;
      break;
    case kBottomRight:
      pStart.x += size;
      pEnd.y -= size;
      break;
    default:
      break;
  }
  CGPathMoveToPoint(path, NULL, pStart.x, pStart.y);
  CGPathAddLineToPoint(path, NULL, point.x, point.y);
  CGPathAddLineToPoint(path, NULL, pEnd.x, pEnd.y);
  return path;
}

- (CGPathRef)newMaskPathForGuideFrame:(CGRect)guideFrame outerFrame:(CGRect)frame {
  UIBezierPath *maskPath = [UIBezierPath bezierPathWithRect:self.bounds];
  [maskPath appendPath:[[UIBezierPath bezierPathWithRoundedRect:guideFrame cornerRadius:16] bezierPathByReversingPath]];
  return CGPathRetain(maskPath.CGPath);
}

- (CGFloat)sizeForBounds:(CGFloat)standardSize {
  if (self.bounds.size.width == 0 || self.bounds.size.width >= kStandardMinimumBoundsWidth) {
    return standardSize;
  }
  else {
#if __LP64__
    return ceil(standardSize * self.bounds.size.width / kStandardMinimumBoundsWidth);
#else
    return ceilf(standardSize * self.bounds.size.width / kStandardMinimumBoundsWidth);
#endif
  }
}

- (CGFloat)lineWidth {
  return [self sizeForBounds:kStandardLineWidth];
}

- (CGFloat)cornerSize {
  return [self sizeForBounds:kStandardCornerSize];
}

- (CGPoint)landscapeVEdgeAdj {
  return CGPointMake([self cornerSize] - kAdjustFudge, 0.0f);
}

- (CGPoint)landscapeHEdgeAdj {
  return CGPointMake(0.0f, [self cornerSize] - kAdjustFudge);
}

// Animate edge layer
- (void)animateEdgeLayer:(CAShapeLayer *)layer 
         toPathFromPoint:(CGPoint)firstPoint 
                 toPoint:(CGPoint)secondPoint 
         adjustedBy:(CGPoint)adjPoint {
  layer.lineWidth = [self lineWidth];
  
  firstPoint = CGPointMake(firstPoint.x + adjPoint.x, firstPoint.y + adjPoint.y);
  secondPoint = CGPointMake(secondPoint.x - adjPoint.x, secondPoint.y - adjPoint.y); 
  CGPathRef newPath = [[self class] newPathFromPoint:firstPoint toPoint:secondPoint];
  [self animateLayer:layer toNewPath:newPath];

  // I used to see occasional crashes stemming from this CGPathRelease. I'm restoring it,
  // since I can no longer reproduce the crashes, and it is a memory leak otherwise. :)
  CGPathRelease(newPath);
}

- (void)animateCornerLayer:(CAShapeLayer *)layer atPoint:(CGPoint)point withPositionType:(CornerPositionType)posType {
  layer.lineWidth = [self lineWidth];
  
  CGPathRef newPath = [[self class] newCornerPathFromPoint:point size:[self cornerSize] positionType:posType];
  [self animateLayer:layer toNewPath:newPath];

  // See above comment on crashes. Same probably applies here. - BPF
  CGPathRelease(newPath);
}

// Animate the layer to a new path.
- (void)animateLayer:(CAShapeLayer *)layer toNewPath:(CGPathRef)newPath {
  if(layer.path) {
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"path"];
    animation.fromValue = (id)layer.path;
    animation.toValue = (__bridge id)newPath;
    animation.duration = self.animationDuration;
    [layer addAnimation:animation forKey:@"animatePath"];
    layer.path = newPath;
  } else {
    SuppressCAAnimation(^{
      layer.path = newPath;
    });
  }
}

- (void)animateCardMask:(CGRect)guideFrame {
  SuppressCAAnimation(^{
    self.backgroundOverlay.frame = self.bounds;
  });
  CGPathRef path = [self newMaskPathForGuideFrame:guideFrame outerFrame:self.bounds];
  UIBezierPath *strokePath = [UIBezierPath bezierPathWithRoundedRect:guideFrame cornerRadius:16];
  for (CAShapeLayer *layer in self.backgroundOverlay.sublayers) {
    if ([layer.name isEqualToString:kStrokeLayerName]) {
      layer.path = strokePath.CGPath;
    }
  }
  [self animateLayer:self.backgroundOverlay toNewPath:path];
  CGPathRelease(path);
}

- (void)setLayerPaths {
  CGRect guideFrame = [self guideFrame];
  if(CGRectIsEmpty(guideFrame)) {
    // don't set an empty guide frame -- this helps keep the animations clean, so that
    // we never animate to or from an empty frame, which looks odd.
    return;
  }

  [self animateCardMask:guideFrame];
}

+ (CGRect)guideFrameForDeviceOrientation:(UIDeviceOrientation)deviceOrientation inViewWithSize:(CGSize)size {
  // Cases whose combinations must be considered when touching this code:
  // 1. card.io running full-screen vs. modal sheet (either Page Sheet or Form Sheet)
  // 2. Device orientation when card.io was launched.
  // 3. Current device orientation.
  // 4. Device orientation-locking: none, portrait, landscape.
  // 5. App constraints in info.plist via UISupportedInterfaceOrientations.
  // Also, when testing, remember there are 2 portrait and 2 landscape orientations.
  
  FrameOrientation       frameOrientation = frameOrientationWithInterfaceOrientation((UIInterfaceOrientation)deviceOrientation);
  UIInterfaceOrientation interfaceOrientation = [UIApplication sharedApplication].statusBarOrientation;
  if (UIInterfaceOrientationIsPortrait(interfaceOrientation)) {
    dmz_rect guideFrame = dmz_guide_frame(frameOrientation, (float)size.width, (float)size.height);
    return CGRectWithDmzRect(guideFrame);
  }
  else {
    dmz_rect guideFrame = dmz_guide_frame(frameOrientation, (float)size.height, (float)size.width);
    return CGRectWithRotatedDmzRect(guideFrame);
  }
}

- (CGRect)guideFrame {
  return [[self class] guideFrameForDeviceOrientation:self.deviceOrientation inViewWithSize:self.bounds.size];
}

- (void)didRotateToDeviceOrientation:(UIDeviceOrientation)deviceOrientation {
  [self setNeedsLayout];

  if (deviceOrientation != self.deviceOrientation) {
    self.deviceOrientation = deviceOrientation;
#if CARDIO_DEBUG
    [self rotateDebugOverlay];
#endif
  }
}

#if CARDIO_DEBUG
- (void)rotateDebugOverlay {
  self.debugOverlay.frame = self.guideFrame;
  
  //  InterfaceToDeviceOrientationDelta delta = orientationDelta(self.interfaceOrientation, self.deviceOrientation);
  //  CGFloat rotation = -rotationForOrientationDelta(delta); // undo the orientation delta
  //  self.debugOverlay.transform = CATransform3DMakeRotation(rotation, 0, 0, 1);
}
#endif

- (void)setVideoFrame:(CardIOVideoFrame *)newFrame {
  _videoFrame = newFrame;
  
  self.edgeScoreTop = kEdgeDecay * self.edgeScoreTop + (1 - kEdgeDecay) * (newFrame.foundTopEdge ? 1.0f : -1.0f);
  self.edgeScoreRight = kEdgeDecay * self.edgeScoreRight + (1 - kEdgeDecay) * (newFrame.foundRightEdge ? 1.0f : -1.0f);
  self.edgeScoreBottom = kEdgeDecay * self.edgeScoreBottom + (1 - kEdgeDecay) * (newFrame.foundBottomEdge ? 1.0f : -1.0f);
  self.edgeScoreLeft = kEdgeDecay * self.edgeScoreLeft + (1 - kEdgeDecay) * (newFrame.foundLeftEdge ? 1.0f : -1.0f);

  // Update the scores with our decay factor
  float allEdgesFoundScore = (newFrame.foundAllEdges ? 1.0f : 0.0f);
  self.allEdgesFoundDecayedScore = kAllEdgesFoundScoreDecay * self.allEdgesFoundDecayedScore + (1.0f - kAllEdgesFoundScoreDecay) * allEdgesFoundScore;
  self.numEdgesFoundDecayedScore = kNumEdgesFoundScoreDecay * self.numEdgesFoundDecayedScore + (1.0f - kNumEdgesFoundScoreDecay) * newFrame.numEdgesFound;

  if (self.allEdgesFoundDecayedScore >= 0.7f) {
    [self showCardFound:YES];
  } else if (self.allEdgesFoundDecayedScore <= 0.1f){
    [self showCardFound:NO];
  }
  
#if CARDIO_DEBUG
  self.debugOverlay.contents = (id)self.videoFrame.debugCardImage.CGImage;
#endif
}

- (void)layoutSublayers {
  SuppressCAAnimation(^{
    [self setLayerPaths];
    
    CGRect guideFrame = [self guideFrame];
    CGFloat left = CGRectGetMinX(guideFrame);
    CGFloat top = CGRectGetMinY(guideFrame);
    CGFloat right = CGRectGetMaxX(guideFrame);
    CGFloat bottom = CGRectGetMaxY(guideFrame);
    CGRect rotatedGuideFrame = CGRectMake(left, top, right - left, bottom - top);
    CGFloat inset = [self lineWidth] / 2;
    rotatedGuideFrame = CGRectInset(rotatedGuideFrame, inset, inset);
    [self.guideLayerDelegate guideLayerDidLayout:rotatedGuideFrame];
    
#if CARDIO_DEBUG
  [self rotateDebugOverlay];
#endif
  });
}

- (void)showCardFound:(BOOL)found {
  if (found) {
    self.backgroundOverlay.fillColor = [UIColor colorWithWhite:0.0f alpha:0.8f].CGColor;
  } else {
    self.backgroundOverlay.fillColor = [UIColor colorWithWhite:0.0f alpha:0.5f].CGColor;
  }
}

@end

#endif
