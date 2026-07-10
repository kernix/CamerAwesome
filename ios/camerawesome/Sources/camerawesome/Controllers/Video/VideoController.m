//
//  VideoController.m
//  camerawesome
//
//  Created by Dimitri Dessus on 17/12/2020.
//

#import "VideoController.h"
#import "AspectRatioUtils.h"

FourCharCode const videoFormat = kCVPixelFormatType_32BGRA;

@implementation VideoController {
  AspectRatio _aspectRatio;
  BOOL _sessionStarted;
}

- (instancetype)init {
  self = [super init];
  _isRecording = NO;
  _isAudioEnabled = YES;
  _isPaused = NO;
  _aspectRatio = Ratio4_3;
  
  return self;
}

# pragma mark - User video interactions

/// Start recording video at given path
- (void)recordVideoAtPath:(NSString *)path captureDevice:(AVCaptureDevice *)device orientation:(NSInteger)orientation audioSetupCallback:(OnAudioSetup)audioSetupCallback videoWriterCallback:(OnVideoWriterSetup)videoWriterCallback options:(CupertinoVideoOptions *)options quality:(VideoRecordingQuality)quality completion:(nonnull void (^)(FlutterError * _Nullable))completion {
  _options = options;
  _recordingQuality = quality;
  _orientation = orientation;
  _captureDevice = device;
  
  // Create audio & video writer
  if (![self setupWriterForPath:path audioSetupCallback:audioSetupCallback options:options completion:completion]) {
    completion([FlutterError errorWithCode:@"VIDEO_ERROR" message:@"impossible to write video at path" details:path]);
    return;
  }
  // Call parent to add delegates for video & audio (if needed)
  videoWriterCallback();
  
  _isRecording = YES;
  _sessionStarted = NO;
  _videoTimeOffset = CMTimeMake(0, 1);
  _audioTimeOffset = CMTimeMake(0, 1);
  _lastVideoSampleTime = kCMTimeInvalid;
  _lastAudioSampleTime = kCMTimeInvalid;
  _videoIsDisconnected = NO;
  _audioIsDisconnected = NO;
  
  // Change video FPS if provided
  if (_options && _options.fps != nil && _options.fps > 0) {
    [self adjustCameraFPS:_options.fps];
  }
}

/// Stop recording video
- (void)stopRecordingVideo:(nonnull void (^)(NSNumber * _Nullable, FlutterError * _Nullable))completion {
  if (_options && _options.fps != nil && _options.fps > 0) {
    // Reset camera FPS
    [self adjustCameraFPS:@(30)];
  }

  @synchronized(self) {
    if (!_isRecording) {
      completion(@(NO), [FlutterError errorWithCode:@"VIDEO_ERROR" message:@"video is not recording" details:@""]);
      return;
    }
    _isRecording = NO;
  }

  AVAssetWriterStatus writerStatus = _videoWriter.status;
  if (writerStatus == AVAssetWriterStatusWriting) {
    [_videoWriterInput markAsFinished];
    if (_audioWriterInput != nil) {
      [_audioWriterInput markAsFinished];
    }
    [_videoWriter finishWritingWithCompletionHandler:^{
      self->_sessionStarted = NO;
      if (self->_videoWriter.status == AVAssetWriterStatusCompleted) {
        completion(@(YES), nil);
      } else {
        completion(@(NO), [FlutterError errorWithCode:@"VIDEO_ERROR" message:@"impossible to completely write video" details:@""]);
      }
    }];
    return;
  }

  _sessionStarted = NO;
  if (writerStatus == AVAssetWriterStatusCompleted) {
    completion(@(YES), nil);
    return;
  }
  completion(@(NO), [FlutterError errorWithCode:@"VIDEO_ERROR" message:@"video is not recording" details:@""]);
}

- (void)pauseVideoRecording {
  _isPaused = YES;
}

- (void)resumeVideoRecording {
  _isPaused = NO;
}

# pragma mark - Audio & Video writers

/// Setup video channel & write file on path
- (BOOL)setupWriterForPath:(NSString *)path audioSetupCallback:(OnAudioSetup)audioSetupCallback options:(CupertinoVideoOptions *)options completion:(nonnull void (^)(FlutterError * _Nullable))completion {
  NSError *error = nil;
  NSURL *outputURL;
  if (path != nil) {
    outputURL = [NSURL fileURLWithPath:path];
  } else {
    return NO;
  }
  if (_isAudioEnabled && !_isAudioSetup) {
    audioSetupCallback();
  }
  
  // Read from options if available
  AVVideoCodecType codecType = [self getBestCodecTypeAccordingOptions:options];
  AVFileType fileType = [self getBestFileTypeAccordingOptions:options];
  CGSize videoSize = [self getBestVideoSizeAccordingQuality: _recordingQuality];
    
  NSDictionary *videoSettings = @{
    AVVideoCodecKey   : codecType,
    AVVideoWidthKey   : @(videoSize.height),
    AVVideoHeightKey  : @(videoSize.width),
  };
  
  _videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
  [_videoWriterInput setTransform:[self getVideoOrientation]];
  
  _videoAdaptor = [AVAssetWriterInputPixelBufferAdaptor
                   assetWriterInputPixelBufferAdaptorWithAssetWriterInput:_videoWriterInput
                   sourcePixelBufferAttributes:@{
    (NSString *)kCVPixelBufferPixelFormatTypeKey: @(videoFormat)
  }];
  
  NSParameterAssert(_videoWriterInput);
  _videoWriterInput.expectsMediaDataInRealTime = YES;
  
  _videoWriter = [[AVAssetWriter alloc] initWithURL:outputURL
                                           fileType:fileType
                                              error:&error];
  NSParameterAssert(_videoWriter);
  if (error) {
    completion([FlutterError errorWithCode:@"VIDEO_ERROR" message:@"impossible to create video writer, check your options" details:error.description]);
    return NO;
  }
  
  [_videoWriter addInput:_videoWriterInput];
  
  if (_isAudioEnabled) {
    AudioChannelLayout acl;
    bzero(&acl, sizeof(acl));
    acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
    NSDictionary *audioOutputSettings = nil;
    
    audioOutputSettings = [NSDictionary
                           dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kAudioFormatMPEG4AAC], AVFormatIDKey,
                           [NSNumber numberWithFloat:44100.0], AVSampleRateKey,
                           [NSNumber numberWithInt:1], AVNumberOfChannelsKey,
                           [NSData dataWithBytes:&acl length:sizeof(acl)],
                           AVChannelLayoutKey, nil];
    _audioWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
                                                           outputSettings:audioOutputSettings];
    _audioWriterInput.expectsMediaDataInRealTime = YES;
    
    [_videoWriter addInput:_audioWriterInput];
  }
  
  return YES;
}

- (CGAffineTransform)getVideoOrientation {
  CGAffineTransform transform;
  
  switch (_orientation) {
    case UIDeviceOrientationLandscapeLeft:
      transform = CGAffineTransformMakeRotation(M_PI_2);
      break;
    case UIDeviceOrientationLandscapeRight:
      transform = CGAffineTransformMakeRotation(-M_PI_2);
      break;
    case UIDeviceOrientationPortraitUpsideDown:
      transform = CGAffineTransformMakeRotation(M_PI);
      break;
    default:
      transform = CGAffineTransformIdentity;
      break;
  }
  
  return transform;
}

/// Append audio data
- (void)newAudioSample:(CMSampleBufferRef)sampleBuffer {
  @synchronized(self) {
    if (!_isRecording) {
      return;
    }
  }

  if (_videoWriter.status != AVAssetWriterStatusWriting) {
    return;
  }
  if (_audioWriterInput.readyForMoreMediaData) {
    if (![_audioWriterInput appendSampleBuffer:sampleBuffer]) {
      //      *error = [FlutterError errorWithCode:@"VIDEO_ERROR" message:@"adding audio channel failed" details:_videoWriter.error];
    }
  }
}

/// Adjust time to sync audio & video
- (CMSampleBufferRef)adjustTime:(CMSampleBufferRef)sample by:(CMTime)offset CF_RETURNS_RETAINED {
  CMItemCount count;
  CMSampleBufferGetSampleTimingInfoArray(sample, 0, nil, &count);
  CMSampleTimingInfo *pInfo = malloc(sizeof(CMSampleTimingInfo) * count);
  CMSampleBufferGetSampleTimingInfoArray(sample, count, pInfo, &count);
  for (CMItemCount i = 0; i < count; i++) {
    pInfo[i].decodeTimeStamp = CMTimeSubtract(pInfo[i].decodeTimeStamp, offset);
    pInfo[i].presentationTimeStamp = CMTimeSubtract(pInfo[i].presentationTimeStamp, offset);
  }
  CMSampleBufferRef sout;
  CMSampleBufferCreateCopyWithNewTiming(nil, sample, count, pInfo, &sout);
  free(pInfo);
  return sout;
}

/// Adjust video preview & recording to specified FPS
- (void)adjustCameraFPS:(NSNumber *)fps {
  NSArray *frameRateRanges = _captureDevice.activeFormat.videoSupportedFrameRateRanges;
  
  if (frameRateRanges.count > 0) {
    AVFrameRateRange *frameRateRange = frameRateRanges.firstObject;
    NSError *error = nil;
    
    if ([_captureDevice lockForConfiguration:&error]) {
      CMTime frameDuration = CMTimeMake(1, [fps intValue]);
      if (CMTIME_COMPARE_INLINE(frameDuration, <=, frameRateRange.maxFrameDuration) && CMTIME_COMPARE_INLINE(frameDuration, >=, frameRateRange.minFrameDuration)) {
        _captureDevice.activeVideoMinFrameDuration = frameDuration;
      }
      [_captureDevice unlockForConfiguration];
    }
  }
}

- (BOOL)canAcceptMediaForWriter:(AVAssetWriter *)writer {
  @synchronized(self) {
    if (!_isRecording || writer == nil) {
      return NO;
    }
  }

  AVAssetWriterStatus status = writer.status;
  return status == AVAssetWriterStatusUnknown || status == AVAssetWriterStatusWriting;
}

- (BOOL)startWriterSessionIfNeededAtTime:(CMTime)time {
  AVAssetWriterStatus status = _videoWriter.status;
  if (status == AVAssetWriterStatusCompleted ||
      status == AVAssetWriterStatusCancelled ||
      status == AVAssetWriterStatusFailed) {
    return NO;
  }

  if (_sessionStarted) {
    return status == AVAssetWriterStatusWriting;
  }

  if (status != AVAssetWriterStatusUnknown) {
    return NO;
  }

  if (![_videoWriter startWriting]) {
    return NO;
  }
  [_videoWriter startSessionAtSourceTime:time];
  _sessionStarted = YES;
  return YES;
}

# pragma mark - Camera Delegates
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection captureVideoOutput:(AVCaptureVideoDataOutput *)captureVideoOutput {

  if (self.isPaused) {
    return;
  }

  if (![self canAcceptMediaForWriter:_videoWriter]) {
    return;
  }

  CFRetain(sampleBuffer);
  CMTime currentSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);

  if (![self startWriterSessionIfNeededAtTime:currentSampleTime]) {
    CFRelease(sampleBuffer);
    return;
  }

  if (output == captureVideoOutput) {
    if (_videoIsDisconnected) {
      _videoIsDisconnected = NO;
      
      if (_videoTimeOffset.value == 0) {
        _videoTimeOffset = CMTimeSubtract(currentSampleTime, _lastVideoSampleTime);
      } else {
        CMTime offset = CMTimeSubtract(currentSampleTime, _lastVideoSampleTime);
        _videoTimeOffset = CMTimeAdd(_videoTimeOffset, offset);
      }

      CFRelease(sampleBuffer);
      return;
    }

    _lastVideoSampleTime = currentSampleTime;

    BOOL canAppendVideo = NO;
    @synchronized(self) {
      canAppendVideo = _isRecording &&
          _videoWriter.status == AVAssetWriterStatusWriting &&
          _videoWriterInput.readyForMoreMediaData;
    }

    if (!canAppendVideo) {
      CFRelease(sampleBuffer);
      return;
    }

    CVPixelBufferRef nextBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferRef croppedBuffer = [self croppedPixelBufferFromBuffer:nextBuffer];
    CVPixelBufferRef bufferToAppend = croppedBuffer != NULL ? croppedBuffer : nextBuffer;
    CMTime nextSampleTime = CMTimeSubtract(_lastVideoSampleTime, _videoTimeOffset);

    @synchronized(self) {
      if (_isRecording &&
          _videoWriter.status == AVAssetWriterStatusWriting &&
          _videoWriterInput.readyForMoreMediaData) {
        [_videoAdaptor appendPixelBuffer:bufferToAppend withPresentationTime:nextSampleTime];
      }
    }

    if (croppedBuffer != NULL) {
      CVPixelBufferRelease(croppedBuffer);
    }
  } else {
    CMTime dur = CMSampleBufferGetDuration(sampleBuffer);
    
    if (dur.value > 0) {
      currentSampleTime = CMTimeAdd(currentSampleTime, dur);
    }
    if (_audioIsDisconnected) {
      _audioIsDisconnected = NO;
      
      if (_audioTimeOffset.value == 0) {
        _audioTimeOffset = CMTimeSubtract(currentSampleTime, _lastAudioSampleTime);
      } else {
        CMTime offset = CMTimeSubtract(currentSampleTime, _lastAudioSampleTime);
        _audioTimeOffset = CMTimeAdd(_audioTimeOffset, offset);
      }

      CFRelease(sampleBuffer);
      return;
    }
    
    _lastAudioSampleTime = currentSampleTime;
    
    if (_audioTimeOffset.value != 0) {
      CFRelease(sampleBuffer);
      sampleBuffer = [self adjustTime:sampleBuffer by:_audioTimeOffset];
    }
    
    [self newAudioSample:sampleBuffer];
  }
  
  CFRelease(sampleBuffer);
}

# pragma mark - Settings converters

- (AVFileType)getBestFileTypeAccordingOptions:(CupertinoVideoOptions *)options {
  AVFileType fileType = AVFileTypeQuickTimeMovie;
  
  if (options && options != (id)[NSNull null]) {
    CupertinoFileType type = options.fileType;
    switch (type) {
      case CupertinoFileTypeQuickTimeMovie:
        fileType = AVFileTypeQuickTimeMovie;
        break;
      case CupertinoFileTypeMpeg4:
        fileType = AVFileTypeMPEG4;
        break;
      case CupertinoFileTypeAppleM4V:
        fileType = AVFileTypeAppleM4V;
        break;
      case CupertinoFileTypeType3GPP:
        fileType = AVFileType3GPP;
        break;
      case CupertinoFileTypeType3GPP2:
        fileType = AVFileType3GPP2;
        break;
      default:
        break;
    }
  }
  
  return fileType;
}

- (AVVideoCodecType)getBestCodecTypeAccordingOptions:(CupertinoVideoOptions *)options {
  AVVideoCodecType codecType = AVVideoCodecTypeH264;
  if (options && options != (id)[NSNull null]) {
    CupertinoCodecType codec = options.codec;
    switch (codec) {
      case CupertinoCodecTypeH264:
        codecType = AVVideoCodecTypeH264;
        break;
      case CupertinoCodecTypeHevc:
        codecType = AVVideoCodecTypeHEVC;
        break;
      case CupertinoCodecTypeHevcWithAlpha:
        codecType = AVVideoCodecTypeHEVCWithAlpha;
        break;
      case CupertinoCodecTypeJpeg:
        codecType = AVVideoCodecTypeJPEG;
        break;
      case CupertinoCodecTypeAppleProRes4444:
        codecType = AVVideoCodecTypeAppleProRes4444;
        break;
      case CupertinoCodecTypeAppleProRes422:
        codecType = AVVideoCodecTypeAppleProRes422;
        break;
      case CupertinoCodecTypeAppleProRes422HQ:
        codecType = AVVideoCodecTypeAppleProRes422HQ;
        break;
      case CupertinoCodecTypeAppleProRes422LT:
        codecType = AVVideoCodecTypeAppleProRes422LT;
        break;
      case CupertinoCodecTypeAppleProRes422Proxy:
        codecType = AVVideoCodecTypeAppleProRes422Proxy;
        break;
      default:
        break;
    }
  }
  return codecType;
}

- (CGSize)getBestVideoSizeAccordingQuality:(VideoRecordingQuality)quality {
  CGSize size;
  switch (quality) {
    case VideoRecordingQualityUhd:
    case VideoRecordingQualityHighest:
      if (@available(iOS 9.0, *)) {
        if ([_captureDevice supportsAVCaptureSessionPreset:AVCaptureSessionPreset3840x2160]) {
          size = CGSizeMake(3840, 2160);
        } else {
          size = CGSizeMake(1920, 1080);
        }
      } else {
        return CGSizeMake(1920, 1080);
      }
      break;
    case VideoRecordingQualityFhd:
      size = CGSizeMake(1920, 1080);
      break;
    case VideoRecordingQualityHd:
      size = CGSizeMake(1280, 720);
      break;
    case VideoRecordingQualitySd:
    case VideoRecordingQualityLowest:
      size = CGSizeMake(960, 540);
      break;
  }

  size = [AspectRatioUtils croppedLandscapeSizeForAspectRatio:_aspectRatio sourceSize:size];
    
  // ensure video output size does not exceed capture session size
  CGSize maxPreviewSize = [AspectRatioUtils croppedLandscapeSizeForAspectRatio:_aspectRatio sourceSize:_previewSize];
  if (size.width > maxPreviewSize.width || size.height > maxPreviewSize.height) {
    size = maxPreviewSize;
  }
  
  return size;
}

- (CVPixelBufferRef)croppedPixelBufferFromBuffer:(CVPixelBufferRef)pixelBuffer {
  if (pixelBuffer == NULL || _aspectRatio == Ratio16_9) {
    return NULL;
  }

  size_t width = CVPixelBufferGetWidth(pixelBuffer);
  size_t height = CVPixelBufferGetHeight(pixelBuffer);
  CGRect cropRect = [AspectRatioUtils previewAlignedCropRectForBufferSize:CGSizeMake(width, height)
                                                              aspectRatio:_aspectRatio];

  if (CGRectEqualToRect(cropRect, CGRectMake(0, 0, width, height))) {
    return NULL;
  }

  if (cropRect.origin.x < 0 || cropRect.origin.y < 0 ||
      CGRectGetMaxX(cropRect) > width || CGRectGetMaxY(cropRect) > height) {
    return NULL;
  }

  CVPixelBufferRef outputBuffer = NULL;
  CVReturn status = kCVReturnSuccess;
  if (_videoAdaptor.pixelBufferPool != NULL) {
    status = CVPixelBufferPoolCreatePixelBuffer(NULL, _videoAdaptor.pixelBufferPool, &outputBuffer);
  }

  if (status != kCVReturnSuccess || outputBuffer == NULL) {
    NSDictionary *pixelBufferAttributes = @{
      (NSString *)kCVPixelBufferPixelFormatTypeKey: @(videoFormat),
      (NSString *)kCVPixelBufferWidthKey: @(cropRect.size.width),
      (NSString *)kCVPixelBufferHeightKey: @(cropRect.size.height),
      (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
    };
    status = CVPixelBufferCreate(kCFAllocatorDefault,
                                 cropRect.size.width,
                                 cropRect.size.height,
                                 videoFormat,
                                 (__bridge CFDictionaryRef)pixelBufferAttributes,
                                 &outputBuffer);
  }

  if (status != kCVReturnSuccess || outputBuffer == NULL) {
    return NULL;
  }

  CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
  CVPixelBufferLockBaseAddress(outputBuffer, 0);

  uint8_t *sourceAddress = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
  uint8_t *destinationAddress = (uint8_t *)CVPixelBufferGetBaseAddress(outputBuffer);
  size_t sourceBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
  size_t destinationBytesPerRow = CVPixelBufferGetBytesPerRow(outputBuffer);
  size_t cropX = (size_t)cropRect.origin.x;
  size_t cropY = (size_t)cropRect.origin.y;
  size_t cropWidth = (size_t)cropRect.size.width;
  size_t cropHeight = (size_t)cropRect.size.height;
  size_t bytesPerPixel = 4;

  for (size_t row = 0; row < cropHeight; row++) {
    memcpy(destinationAddress + row * destinationBytesPerRow,
           sourceAddress + (cropY + row) * sourceBytesPerRow + cropX * bytesPerPixel,
           cropWidth * bytesPerPixel);
  }

  CVPixelBufferUnlockBaseAddress(outputBuffer, 0);
  CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

  return outputBuffer;
}

# pragma mark - Setter
- (void)setIsAudioEnabled:(bool)isAudioEnabled {
  _isAudioEnabled = isAudioEnabled;
}
- (void)setIsAudioSetup:(bool)isAudioSetup {
  _isAudioSetup = isAudioSetup;
}

- (void)setPreviewSize:(CGSize)previewSize {
  _previewSize = previewSize;
}

- (void)setAspectRatio:(AspectRatio)aspectRatio {
  _aspectRatio = aspectRatio;
}

- (void)setVideoIsDisconnected:(bool)videoIsDisconnected {
  _videoIsDisconnected = videoIsDisconnected;
}

- (void)setAudioIsDisconnected:(bool)audioIsDisconnected {
  _audioIsDisconnected = audioIsDisconnected;
}

/// Update capture device reference and re-apply FPS if recording with custom FPS
/// This should be called after switching cameras during recording to ensure
/// the new camera device uses the same FPS as the original recording settings.
- (void)updateCaptureDevice:(AVCaptureDevice *)device {
  _captureDevice = device;

  // Re-apply custom FPS if recording is in progress and custom FPS was specified
  if (_isRecording && _options && _options.fps != nil && _options.fps.intValue > 0) {
    [self adjustCameraFPS:_options.fps];
  }
}

@end
