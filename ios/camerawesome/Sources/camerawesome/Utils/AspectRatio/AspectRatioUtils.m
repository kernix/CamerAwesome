//
//  AspectRatioUtils.m
//  camerawesome
//
//  Created by Dimitri Dessus on 29/03/2023.
//

#import "AspectRatioUtils.h"

@implementation AspectRatioUtils

+ (AspectRatio)convertAspectRatio:(NSString *)aspectRatioStr {
  AspectRatio aspectRatioMode;
  if ([aspectRatioStr isEqualToString:@"RATIO_4_3"]) {
    aspectRatioMode = Ratio4_3;
  } else if ([aspectRatioStr isEqualToString:@"RATIO_16_9"]) {
    aspectRatioMode = Ratio16_9;
  } else {
    aspectRatioMode = Ratio1_1;
  }
  return aspectRatioMode;
}

+ (CGFloat)landscapeAspectRatioValue:(AspectRatio)ratio {
  switch (ratio) {
    case Ratio16_9:
      return 16.0 / 9.0;
    case Ratio4_3:
      return 4.0 / 3.0;
    case Ratio1_1:
      return 1.0;
  }
}

+ (CGFloat)bufferAspectRatioValue:(AspectRatio)ratio bufferSize:(CGSize)bufferSize {
  if (bufferSize.height > bufferSize.width) {
    switch (ratio) {
      case Ratio16_9:
        return 9.0 / 16.0;
      case Ratio4_3:
        return 3.0 / 4.0;
      case Ratio1_1:
        return 1.0;
    }
  }
  return [self landscapeAspectRatioValue:ratio];
}

+ (CGSize)croppedLandscapeSizeForAspectRatio:(AspectRatio)ratio sourceSize:(CGSize)sourceSize {
  if (ratio == Ratio16_9 || sourceSize.width <= 0 || sourceSize.height <= 0) {
    return sourceSize;
  }

  CGFloat targetRatio = [self landscapeAspectRatioValue:ratio];
  CGFloat currentRatio = sourceSize.width / sourceSize.height;

  if (fabs(currentRatio - targetRatio) < 0.01) {
    return sourceSize;
  }

  if (currentRatio > targetRatio) {
    return CGSizeMake(sourceSize.height * targetRatio, sourceSize.height);
  }

  return CGSizeMake(sourceSize.width, sourceSize.width / targetRatio);
}

+ (CGRect)centerCropRectForBufferSize:(CGSize)bufferSize aspectRatio:(AspectRatio)ratio {
  if (ratio == Ratio16_9 || bufferSize.width <= 0 || bufferSize.height <= 0) {
    return CGRectMake(0, 0, bufferSize.width, bufferSize.height);
  }

  CGFloat targetRatio = [self bufferAspectRatioValue:ratio bufferSize:bufferSize];
  CGFloat bufferRatio = bufferSize.width / bufferSize.height;
  CGFloat cropWidth;
  CGFloat cropHeight;

  if (bufferRatio > targetRatio) {
    cropHeight = bufferSize.height;
    cropWidth = cropHeight * targetRatio;
  } else {
    cropWidth = bufferSize.width;
    cropHeight = cropWidth / targetRatio;
  }

  CGFloat x = (bufferSize.width - cropWidth) / 2.0;
  CGFloat y = (bufferSize.height - cropHeight) / 2.0;
  return CGRectMake(x, y, cropWidth, cropHeight);
}

+ (CGRect)previewAlignedCropRectForBufferSize:(CGSize)bufferSize aspectRatio:(AspectRatio)ratio {
  // Biclic masks the top of the 16:9 stream with a bar of height (16:9 - target) / 2,
  // then shows exactly the target aspect ratio below it (top-aligned on the 16:9 frame).
  if (ratio == Ratio16_9 || bufferSize.width <= 0 || bufferSize.height <= 0) {
    return CGRectMake(0, 0, bufferSize.width, bufferSize.height);
  }

  CGFloat targetRatio = [self bufferAspectRatioValue:ratio bufferSize:bufferSize];
  CGFloat bufferRatio = bufferSize.width / bufferSize.height;
  CGFloat cropWidth;
  CGFloat cropHeight;

  if (bufferRatio > targetRatio) {
    cropHeight = bufferSize.height;
    cropWidth = cropHeight * targetRatio;
  } else {
    cropWidth = bufferSize.width;
    cropHeight = cropWidth / targetRatio;
  }

  CGFloat x = (bufferSize.width - cropWidth) / 2.0;

  if (bufferSize.height > bufferSize.width) {
    CGFloat fullHeight16by9 = bufferSize.width / (9.0 / 16.0);
    CGFloat topInset = MAX(0, (fullHeight16by9 - cropHeight) / 2.0);
    return CGRectMake(x, topInset, cropWidth, cropHeight);
  }

  CGFloat y = (bufferSize.height - cropHeight) / 2.0;
  return CGRectMake(x, y, cropWidth, cropHeight);
}

@end
