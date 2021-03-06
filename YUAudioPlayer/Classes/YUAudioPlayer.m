//
//  YUAudioPlayer.m
//  YUAudioPlayer
//
//  Created by duanjitong on 14-8-18.
//  Copyright (c) 2014年 duanjitong. All rights reserved.
//

#import "YUAudioPlayer.h"
#import "YUAudioDataNT.h"
#import "YUAudioDataLocal.h"
#import "YUAudioQueue.h"
#import "YUAudioStream.h"

@interface YUAudioPlayer()<YUAudioDataDelegate,YUAudioStreamDelegate,YUAudioPropertyDelegate>{
    NSInteger audioVersion;
    NSMutableDictionary *audioQueues;
    NSMutableDictionary *audioStreams;
    BOOL shouldExit;
}
@property(nonatomic,retain) YUAudioDataBase *audioData;
@property(nonatomic,retain) YUAudioQueue *audioQueue;
@property(nonatomic,retain) YUAudioStream *audioStream;
@property(nonatomic,retain) YUAudioProperty* audioProperty;
@end

@implementation YUAudioPlayer
static NSMutableArray *playerArr;
- (instancetype)init
{
    self = [super init];
    if (self) {
        self.audioProperty=[[YUAudioProperty alloc] init];
        self.audioProperty.audioPropertyDelegate=self;
        audioVersion=0;
        audioQueues=[[NSMutableDictionary alloc] init];
        audioStreams=[[NSMutableDictionary alloc] init];
        if (!playerArr) {
            playerArr=[[NSMutableArray alloc] init];
        }
        shouldExit=NO;
        [playerArr addObject:self];
    }
    return self;
}



#pragma mark Play Pause Stop


-(void) playWithUrl:(NSString*)urlStr{
    YUAudioDataBase *audioData;
    if([urlStr.lowercaseString hasPrefix:@"http"]){
        audioData=[[YUAudioDataNT alloc] init];
    }else{
        audioData=[[YUAudioDataLocal alloc] init];
    }
    audioData.urlStr=urlStr;
    [self playWithAudioData:audioData];
}

-(void) playWithAudioData:(YUAudioDataBase*)audioData{
    if (_audioProperty) {
        [_audioProperty clean];
    }
    if (self.audioQueue) {
        [_audioQueue stop];
        self.audioQueue=nil;
    }
    if (_audioData) {
        [_audioData cancel];
        _audioData.audioProperty=nil;
        self.audioData=nil;
    }
    if (_audioStream) {
        _audioStream.audioStreamDelegate=nil;
        _audioStream.audioProperty=nil;
        [_audioStream close];
        self.audioStream=nil;
    }
    if(!audioData){
        ///播放错误
        [self.audioProperty error:YUAudioError_AD_Nil];
        return;
    }
    if (![playerArr containsObject:self]) {
        shouldExit=NO;
        [playerArr addObject:self];
    }
    self.audioData=audioData;
    self.audioData.audioVersion=++audioVersion;
    self.audioData.audioProperty=self.audioProperty;
    self.audioData.audioDataDelegate=self;
    [self.audioData start];
    _audioProperty.state=YUAudioState_Waiting;
}

-(void)play{
    if (_audioQueue) {
        [_audioQueue start];
    }
}

-(void)pause{
    if (_audioQueue) {
        [_audioQueue pause];
    }
}

-(void)stop{
    shouldExit=YES;
    if (_audioQueue) {
        [_audioQueue stop];
        _audioQueue.audioProperty=nil;
        self.audioQueue=nil;
        self.audioProperty=nil;
    }
    else{
        _audioProperty.state=YUAudioState_Stop;
    }
    if (_audioData) {
        [_audioData cancel];
        _audioData.audioProperty=nil;
        self.audioData=nil;
    }
    if (_audioStream) {
        _audioStream.audioStreamDelegate=nil;
        _audioStream.audioProperty=nil;
        [_audioStream close];
        self.audioStream=nil;
    }
}

-(void)seekToTime:(double)seekToTime{
    if (!_audioStream) {
        return;
    }
    if (!_audioQueue) {
        return;
    }
    [_audioStream getSeekToOffset:seekToTime];
    _audioQueue.seekTime=self.audioStream.seekTime;
    __block YUAudioPlayer *gcdSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [gcdSelf.audioData seekToOffset:gcdSelf.audioStream.seekByteOffset];
    });
}

-(double)duration{
    if (!_audioStream) {
        return 0;
    }
    return _audioStream.duration;
}

-(double)currentTime{
    if (!_audioQueue) {
        return 0;
    }
    return _audioQueue.currentTime;
}

-(YUAudioPlayerState)state{
    return _audioProperty.state;
}

#pragma mark YUAudioPropertyDelegate

-(void)audioProperty_Error:(NSError *)error{
    if (_audioProperty.error) {
        [self performSelectorOnMainThread:@selector(stop) withObject:nil waitUntilDone:NO];
    }
}

-(void)audioProperty_StateChanged:(YUAudioPlayerState)state{
    if (self.audioPlayerDelegate) {
        [self.audioPlayerDelegate audioPlayer_StateChanged:_audioProperty.state error:_audioProperty.error];
        if (_audioProperty.error) {
            _audioProperty.error=nil;
        }
    }
}

#pragma mark YUAudioDataDelegate

-(void)audioData_FileType:(YUAudioDataBase*)currAudioData fileType:(AudioFileTypeID)fileTypeHint{
    if (currAudioData!=self.audioData) {
        return;
    }
    if (!_audioStream){
        self.audioStream=[[YUAudioStream alloc] init];
        _audioStream.audioProperty=self.audioProperty;
        _audioStream.audioStreamDelegate=self;
        _audioStream.audioVersion=self.audioData.audioVersion;
        [audioStreams setObject:_audioStream forKey:[NSString stringWithFormat:@"%ld",(long)self.audioData.audioVersion]];
    }
}

-(void)audioData_Arrived:(YUAudioDataBase*)currAudioData data:(NSData *)data contine:(BOOL)isContine{
    if (currAudioData!=self.audioData) {
        return;
    }
    UInt32 flags=0;
    if (!isContine) {
        flags=kAudioFileStreamParseFlag_Discontinuity;
        [self.audioQueue seeked];
    }
    [self.audioStream audioStreamParseBytes:data flags:flags];
}

-(void)audioData_Finished:(YUAudioDataBase*)currAudioData error:(NSError *)error{
    if (currAudioData!=self.audioData) {
        return;
    }
    if (_audioQueue) {
        _audioQueue.loadFinished=YES;
    }
}

-(void)audioData_ShouldExit:(YUAudioDataBase*)currAudioData{
    [audioQueues removeObjectForKey:[NSString stringWithFormat:@"%ld",(long)currAudioData.audioVersion]];
    [audioStreams removeObjectForKey:[NSString stringWithFormat:@"%ld",(long)currAudioData.audioVersion]];
    if (shouldExit) {
        [playerArr removeObject:self];
    }
}

#pragma mark YUAudioStreamDelegate

-(void)audioStream_ReadyToProducePackets{
    if (!self.audioQueue) {
        self.audioQueue=[[YUAudioQueue alloc] initWithAudioDesc:self.audioStream.audioDesc];
        _audioQueue.audioProperty=self.audioProperty;
        _audioQueue.audioVersion=self.audioData.audioVersion;
        [audioQueues setObject:_audioQueue forKey:[NSString stringWithFormat:@"%ld",(long)self.audioData.audioVersion]];
    }
}

-(void)audioStream_Packets:(NSData *)data packetNum:(UInt32)packetCount packetDescs:(AudioStreamPacketDescription *)inPacketDescs{
    [self.audioQueue enqueueBuffer:data packetNum:packetCount packetDescs:inPacketDescs];
}

- (void)dealloc
{
    
}

@end
