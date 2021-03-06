//
//  ccAssetReaderManager.m
//  视频流
//
//  Created by cc on 2019/12/25.
//  Copyright © 2019 cc. All rights reserved.
//

#import "ccAssetWriterManager.h"

@interface ccAssetWriterManager ()

@property (nonatomic,strong) NSURL *videoUrl;
@property (nonatomic,strong) NSURL *videoUrl_input;
@property (nonatomic,assign) CGSize naturalSize;
//媒体读取对象
@property (nonatomic,strong) AVAssetWriter *writer;
//加载轨道及配置
@property (nonatomic,strong) AVAssetWriterInput *assetWriterInput_video;
@property (nonatomic,strong) AVAssetWriterInput *assetWriterInput_audio;
@property (nonatomic,strong) AVAssetWriterInputPixelBufferAdaptor *adaptor;
//资源配置
@property (nonatomic,strong) NSDictionary *videoSetting;
@property (nonatomic,strong) NSDictionary *audioSetting;

@property (nonatomic,strong) dispatch_group_t group;
@property (nonatomic,strong) dispatch_queue_t queue_video;
@property (nonatomic,strong) dispatch_queue_t queue_audio;

@end

@implementation ccAssetWriterManager

+ (instancetype)initWriter:(NSString *)outPutPath inputPath:(NSString*)inputPath{
    
    ccAssetWriterManager* manager = [[ccAssetWriterManager alloc] init];
    manager.videoUrl = [NSURL fileURLWithPath:outPutPath];
    manager.videoUrl_input = [NSURL fileURLWithPath:inputPath];
    
    manager.group = dispatch_group_create();
    manager.queue_video = dispatch_queue_create("queue_video", DISPATCH_QUEUE_CONCURRENT);
    manager.queue_audio = dispatch_queue_create("queue_audio", DISPATCH_QUEUE_CONCURRENT);
    
    AVAsset* asset = [AVAsset assetWithURL:[NSURL fileURLWithPath:inputPath]];
    //需要根据原视频的旋转角度旋转
    manager.assetWriterInput_video.transform = [manager getVideoOrientationWithAsset:asset];
    
    if ([manager.writer canAddInput:manager.assetWriterInput_video]) {
        [manager.writer addInput:manager.assetWriterInput_video];
    }
    if ([manager.writer canAddInput:manager.assetWriterInput_audio]) {
        [manager.writer addInput:manager.assetWriterInput_audio];
    }
    [manager adaptor];
    
    [manager.writer startWriting];
    [manager.writer startSessionAtSourceTime:kCMTimeZero];
    
    return manager;
}

// 开始写入
- (void)pushVideoBuffer:(CVPixelBufferRef)buffer pts:(CMTime)pts{
    
    [NSThread sleepForTimeInterval:0.005];
    if (self.assetWriterInput_video.readyForMoreMediaData) {
        
        NSLog(@"插入图片:%f",CMTimeGetSeconds(pts));
          if (buffer) {
              [_adaptor appendPixelBuffer:buffer withPresentationTime:pts];
              CFRelease(buffer);
              buffer = NULL;
          }
    }else{
        NSLog(@"！！！！！无法插入图片:%f---%ld",CMTimeGetSeconds(pts),(long)self.writer.status);
    }
}

- (void)pushAudioBuffer:(CMSampleBufferRef)buffer{
    
    if (self.assetWriterInput_audio.readyForMoreMediaData) {
        if (buffer) {
            [self.assetWriterInput_audio appendSampleBuffer:buffer];
            CFRelease(buffer);
            buffer = NULL;
        }
    }
}

- (void)videoFinish{
    [self.assetWriterInput_video markAsFinished];
}
- (void)audioFinish{
    [self.assetWriterInput_audio markAsFinished];
}
- (void)finishHandle:(void(^)(bool))handle{
    //队列执行完成
    [self.writer finishWritingWithCompletionHandler:^{
        AVAssetWriterStatus status = self.writer.status;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (handle) {
                handle(status == AVAssetWriterStatusCompleted);
            }
        });
    }];
}

- (void)cancel{
    [self.writer cancelWriting];
}
//获取视频旋转角度
- (CGSize)getVideoOutPutNaturalSizeWithAsset:(AVAsset*)asset{
    
    NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    AVAssetTrack *videoTrack = [tracks objectAtIndex:0];
    CGFloat width = videoTrack.naturalSize.width;
    CGFloat height = videoTrack.naturalSize.height;
    
    CGSize size = CGSizeZero;
    CGAffineTransform videoTransform = videoTrack.preferredTransform;//矩阵旋转角度
    
    if (videoTransform.a == 0 && videoTransform.b == 1.0 && videoTransform.c == -1.0 && videoTransform.d == 0) {
        size = CGSizeMake(height, width);
    }
    if (videoTransform.a == 0 && videoTransform.b == -1.0 && videoTransform.c == 1.0 && videoTransform.d == 0) {
        size = CGSizeMake(height, width);
    }
    if (videoTransform.a == 1.0 && videoTransform.b == 0 && videoTransform.c == 0 && videoTransform.d == 1.0) {
        size = CGSizeMake(width, height);
    }
    if (videoTransform.a == -1.0 && videoTransform.b == 0 && videoTransform.c == 0 && videoTransform.d == -1.0) {
        size = CGSizeMake(width, height);
    }
    
    return size;
}

//获取视频旋转角度
- (CGAffineTransform)getVideoOrientationWithAsset:(AVAsset*)asset{
    
    NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    AVAssetTrack *videoTrack = [tracks objectAtIndex:0];
    return videoTrack.preferredTransform;
}

-(AVAssetWriter *)writer{
    if (!_writer) {
        _writer = [[AVAssetWriter alloc] initWithURL:self.videoUrl fileType:AVFileTypeMPEG4 error:nil];
    }
    return _writer;
}
-(AVAssetWriterInputPixelBufferAdaptor *)adaptor{
    if (!_adaptor) {
        CGSize size = [self getVideoOutPutNaturalSizeWithAsset:[AVAsset assetWithURL:self.videoUrl_input]];
        NSDictionary *dic = @{
            (id)kCVPixelBufferPixelFormatTypeKey:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA],
            AVVideoCodecKey :  AVVideoCodecTypeH264,
            AVVideoWidthKey :  @(size.width),
            AVVideoHeightKey : @(size.height),
            (id)kCVPixelFormatOpenGLESCompatibility : @(NO)
        };
        _adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:self.assetWriterInput_video sourcePixelBufferAttributes:dic];
    }
    return _adaptor;
}
-(AVAssetWriterInput *)assetWriterInput_video{
    if (!_assetWriterInput_video) {
        
        CGSize size = [self getVideoOutPutNaturalSizeWithAsset:[AVAsset assetWithURL:self.videoUrl_input]];
        self.videoSetting = @{
            AVVideoCodecKey :  AVVideoCodecTypeH264,
            AVVideoWidthKey :  @(size.width),
            AVVideoHeightKey : @(size.height)
        };
        _assetWriterInput_video = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:self.videoSetting];
        _assetWriterInput_video.expectsMediaDataInRealTime = YES;
    }
    return _assetWriterInput_video;
}
-(AVAssetWriterInput *)assetWriterInput_audio{
    if (!_assetWriterInput_audio) {
        
        self.audioSetting = @{
            AVFormatIDKey :          @(kAudioFormatMPEG4AAC),
            AVNumberOfChannelsKey :  @(2),
            AVSampleRateKey :        @(44100),
            AVEncoderBitRateKey :    @(64000),
        };
        
        _assetWriterInput_audio = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:self.audioSetting];
    }
    return _assetWriterInput_audio;
}
@end
