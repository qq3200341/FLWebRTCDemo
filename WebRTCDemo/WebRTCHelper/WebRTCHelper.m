//
//  WebRTCHelper.m
//  WebRTCDemo
//
//  Created by qq3200341 on 16/8/12.
//  Copyright © 2016年 maipu. All rights reserved.
//

#import "WebRTCHelper.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

typedef enum : NSUInteger {
    RoleCaller,
    RoleCallee,
} Role;

@interface WebRTCHelper ()<RTCPeerConnectionDelegate>

@end

@implementation WebRTCHelper
{
    SRWebSocket *_socket;
    NSString *_server;
    NSString *_room;
    
    RTCPeerConnectionFactory *_factory;
    RTCMediaStream *_localStream;
    
    NSString *_myId;
    NSMutableDictionary *_connectionDic;
    NSMutableArray *_connectionIdArray;
    NSString *_currentId;
    Role _role;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _connectionDic = [NSMutableDictionary dictionary];
        _connectionIdArray = [NSMutableArray array];
    }
    return self;
}

/**
 *  与服务器建立连接
 *
 *  @param server 服务器地址
 *  @param room   房间号
 */
- (void)connectServer:(NSString *)server room:(NSString *)room
{
    _server = server;
    _room = room;
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"ws://%@:3000",server]] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
    _socket = [[SRWebSocket alloc] initWithURLRequest:request];
    _socket.delegate = self;
    [_socket open];
}
/**
 *  加入房间
 *
 *  @param room 房间号
 */
- (void)joinRoom:(NSString *)room
{
    if (_socket.readyState == SR_OPEN)
    {
        NSDictionary *dic = @{@"eventName": @"__join", @"data": @{@"room": room}};
        NSData *data = [NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:nil];
        [_socket send:data];
    }
}
/**
 *  退出房间
 */
- (void)exitRoom
{
    _localStream = nil;
    [_connectionIdArray enumerateObjectsUsingBlock:^(NSString *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [self closePeerConnection:obj];
    }];
    [_socket close];
}
/**
 *  关闭peerConnection
 *
 *  @param connectionId <#connectionId description#>
 */
- (void)closePeerConnection:(NSString *)connectionId
{
    RTCPeerConnection *peerConnection = [_connectionDic objectForKey:connectionId];
    if (peerConnection)
    {
        [peerConnection close];
    }
    [_connectionIdArray removeObject:connectionId];
    [_connectionDic removeObjectForKey:connectionId];
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([_delegate respondsToSelector:@selector(webRTCHelper:closeWithUserId:)])
        {
            [_delegate webRTCHelper:self closeWithUserId:connectionId];
        }
    });
}
/**
 *  创建本地流
 */
- (void)createLocalStream
{
    _localStream = [_factory mediaStreamWithStreamId:@"ARDAMS"];
    //音频
    RTCAudioTrack *audioTrack = [_factory audioTrackWithTrackId:@"ARDAMSa0"];
    [_localStream addAudioTrack:audioTrack];
    //视频
    
    NSArray *deviceArray = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice *device = [deviceArray lastObject];
    //检测摄像头权限
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if(authStatus == AVAuthorizationStatusRestricted || authStatus == AVAuthorizationStatusDenied)
    {
        NSLog(@"相机访问受限");
        if ([_delegate respondsToSelector:@selector(webRTCHelper:setLocalStream:userId:)])
        {
            [_delegate webRTCHelper:self setLocalStream:nil userId:_myId];
        }
    }
    else
    {
        if (device)
        {
            RTCVideoSource *videoSource = [_factory avFoundationVideoSourceWithConstraints:[self localVideoConstraints]];
            RTCVideoTrack *videoTrack = [_factory videoTrackWithSource:videoSource trackId:@"ARDAMSv0"];
            
            [_localStream addVideoTrack:videoTrack];
            if ([_delegate respondsToSelector:@selector(webRTCHelper:setLocalStream:userId:)])
            {
                [_delegate webRTCHelper:self setLocalStream:_localStream userId:_myId];
            }
        }
        else
        {
            NSLog(@"该设备不能打开摄像头");
            if ([_delegate respondsToSelector:@selector(webRTCHelper:setLocalStream:userId:)])
            {
                [_delegate webRTCHelper:self setLocalStream:nil userId:_myId];
            }
        }
    }
}
/**
 *  视频的相关约束
 */
- (RTCMediaConstraints *)localVideoConstraints
{
    return nil;
//    RTCPair *maxWidth = [[RTCPair alloc] initWithKey:@"maxWidth" value:@"640"];
//    RTCPair *minWidth = [[RTCPair alloc] initWithKey:@"minWidth" value:@"640"];
//    
//    RTCPair *maxHeight = [[RTCPair alloc] initWithKey:@"maxHeight" value:@"480"];
//    RTCPair *minHeight = [[RTCPair alloc] initWithKey:@"minHeight" value:@"480"];
//    
//    RTCPair *minFrameRate = [[RTCPair alloc] initWithKey:@"minFrameRate" value:@"15"];
//    
//    NSArray *mandatory = @[maxWidth, minWidth, maxHeight, minHeight, minFrameRate];
//    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:mandatory optionalConstraints:nil];
//    return constraints;
}
/**
 *  为所有连接创建offer
 */
- (void)createOffers
{
    [_connectionDic enumerateKeysAndObjectsUsingBlock:^(NSString *key, RTCPeerConnection *obj, BOOL * _Nonnull stop) {
        _currentId = key;
        _role = RoleCaller;
        __weak RTCPeerConnection *weakPeerConnection = obj;
        [obj offerForConstraints:[self offerOranswerConstraint] completionHandler:^(RTCSessionDescription * _Nullable sdp, NSError * _Nullable error) {
            if (error)
            {
                NSLog(@"%@",error);
            }
            else
            {
                RTCSessionDescription *newSdp = [self descriptionForDescription:sdp preferredVideoCodec:@"H264"];
                __weak RTCPeerConnection *weakPeerConnection2 = weakPeerConnection;
                [weakPeerConnection setLocalDescription:newSdp completionHandler:^(NSError * _Nullable error) {
                    if (error)
                    {
                        NSLog(@"%@",error);
                    }
                    else
                    {
                        NSString *sdpString = weakPeerConnection2.localDescription.sdp;
                        NSDictionary *dic = @{@"eventName": @"__offer", @"data": @{@"sdp": @{@"type": @"offer", @"sdp": sdpString}, @"socketId": _currentId}};
                        NSData *data = [NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:nil];
                        [_socket send:data];
                    }
                }];
            }
        }];
    }];
}
/**
 *  为所有连接添加流
 */
- (void)addStreams
{
    [_connectionDic enumerateKeysAndObjectsUsingBlock:^(NSString *key, RTCPeerConnection *obj, BOOL * _Nonnull stop) {
        if (!_localStream)
        {
            [self createLocalStream];
        }
        [obj addStream:_localStream];
    }];
}
/**
 *  创建所有连接
 */
- (void)createPeerConnections
{
    [_connectionIdArray enumerateObjectsUsingBlock:^(NSString *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        RTCPeerConnection *connection = [self createPeerConnection:obj];
        [_connectionDic setObject:connection forKey:obj];
    }];
}
/**
 *  创建点对点连接
 *
 *  @param connectionId <#connectionId description#>
 *
 *  @return <#return value description#>
 */
- (RTCPeerConnection *)createPeerConnection:(NSString *)connectionId
{
    if (!_factory)
    {
        _factory = [[RTCPeerConnectionFactory alloc] init];
    }
    RTCConfiguration *config = [[RTCConfiguration alloc] init];
    RTCPeerConnection *connection = [_factory peerConnectionWithConfiguration:config constraints:[self peerConnectionConstraints] delegate:self];
    return connection;
}
/**
 *  peerConnection约束
 *
 *  @return <#return value description#>
 */
- (RTCMediaConstraints *)peerConnectionConstraints
{
    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:nil optionalConstraints:@{@"DtlsSrtpKeyAgreement" : @"true"}];
    return constraints;
}
/**
 *  设置offer/answer的约束
 */
- (RTCMediaConstraints *)offerOranswerConstraint
{
    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:@{@"OfferToReceiveAudio" : @"true",@"OfferToReceiveVideo" : @"true"} optionalConstraints:nil];
    return constraints;
}

#pragma mark--Tool
// Updates the original SDP description to instead prefer the specified video
// codec. We do this by placing the specified codec at the beginning of the
// codec list if it exists in the sdp.
- (RTCSessionDescription *)descriptionForDescription:(RTCSessionDescription *)description preferredVideoCodec:(NSString *)codec
{
    NSString *sdpString = description.sdp;
    NSString *lineSeparator = @"\n";
    NSString *mLineSeparator = @" ";
    // Copied from PeerConnectionClient.java.
    // TODO(tkchin): Move this to a shared C++ file.
    NSMutableArray *lines =
    [NSMutableArray arrayWithArray:
     [sdpString componentsSeparatedByString:lineSeparator]];
    NSInteger mLineIndex = -1;
    NSString *codecRtpMap = nil;
    // a=rtpmap:<payload type> <encoding name>/<clock rate>
    // [/<encoding parameters>]
    NSString *pattern =
    [NSString stringWithFormat:@"^a=rtpmap:(\\d+) %@(/\\d+)+[\r]?$", codec];
    NSRegularExpression *regex =
    [NSRegularExpression regularExpressionWithPattern:pattern
                                              options:0
                                                error:nil];
    for (NSInteger i = 0; (i < lines.count) && (mLineIndex == -1 || !codecRtpMap);
         ++i) {
        NSString *line = lines[i];
        if ([line hasPrefix:@"m=video"]) {
            mLineIndex = i;
            continue;
        }
        NSTextCheckingResult *codecMatches =
        [regex firstMatchInString:line
                          options:0
                            range:NSMakeRange(0, line.length)];
        if (codecMatches) {
            codecRtpMap =
            [line substringWithRange:[codecMatches rangeAtIndex:1]];
            continue;
        }
    }
    if (mLineIndex == -1) {
        RTCLog(@"No m=video line, so can't prefer %@", codec);
        return description;
    }
    if (!codecRtpMap) {
        RTCLog(@"No rtpmap for %@", codec);
        return description;
    }
    NSArray *origMLineParts =
    [lines[mLineIndex] componentsSeparatedByString:mLineSeparator];
    if (origMLineParts.count > 3) {
        NSMutableArray *newMLineParts =
        [NSMutableArray arrayWithCapacity:origMLineParts.count];
        NSInteger origPartIndex = 0;
        // Format is: m=<media> <port> <proto> <fmt> ...
        [newMLineParts addObject:origMLineParts[origPartIndex++]];
        [newMLineParts addObject:origMLineParts[origPartIndex++]];
        [newMLineParts addObject:origMLineParts[origPartIndex++]];
        [newMLineParts addObject:codecRtpMap];
        for (; origPartIndex < origMLineParts.count; ++origPartIndex) {
            if (![codecRtpMap isEqualToString:origMLineParts[origPartIndex]]) {
                [newMLineParts addObject:origMLineParts[origPartIndex]];
            }
        }
        NSString *newMLine =
        [newMLineParts componentsJoinedByString:mLineSeparator];
        [lines replaceObjectAtIndex:mLineIndex
                         withObject:newMLine];
    } else {
        RTCLogWarning(@"Wrong SDP media description format: %@", lines[mLineIndex]);
    }
    NSString *mangledSdpString = [lines componentsJoinedByString:lineSeparator];
    return [[RTCSessionDescription alloc] initWithType:description.type
                                                   sdp:mangledSdpString];
}

#pragma mark--RTCPeerConnectionDelegate
/** Called when the SignalingState changed. */
- (void)peerConnection:(RTCPeerConnection *)peerConnection
didChangeSignalingState:(RTCSignalingState)stateChanged
{
    NSLog(@"%s",__func__);
    NSLog(@"%ld", (long)stateChanged);
}

/** Called when media is received on a new stream from remote peer. */
- (void)peerConnection:(RTCPeerConnection *)peerConnection
          didAddStream:(RTCMediaStream *)stream
{
    NSLog(@"%s",__func__);
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([_delegate respondsToSelector:@selector(webRTCHelper:addRemoteStream:userId:)])
        {
            [_delegate webRTCHelper:self addRemoteStream:stream userId:_currentId];
        }
    });
}

/** Called when a remote peer closes a stream. */
- (void)peerConnection:(RTCPeerConnection *)peerConnection
       didRemoveStream:(RTCMediaStream *)stream
{
    NSLog(@"%s",__func__);
}

/** Called when negotiation is needed, for example ICE has restarted. */
- (void)peerConnectionShouldNegotiate:(RTCPeerConnection *)peerConnection
{
    NSLog(@"%s",__func__);
}

/** Called any time the IceConnectionState changes. */
- (void)peerConnection:(RTCPeerConnection *)peerConnection
didChangeIceConnectionState:(RTCIceConnectionState)newState
{
    NSLog(@"%s",__func__);
    NSLog(@"%ld", (long)newState);
}

/** Called any time the IceGatheringState changes. */
- (void)peerConnection:(RTCPeerConnection *)peerConnection
didChangeIceGatheringState:(RTCIceGatheringState)newState
{
    NSLog(@"%s",__func__);
    NSLog(@"%ld", (long)newState);
}

/** New ice candidate has been found. */
- (void)peerConnection:(RTCPeerConnection *)peerConnection
didGenerateIceCandidate:(RTCIceCandidate *)candidate
{
    NSLog(@"%s",__func__);
    NSDictionary *dic = @{@"eventName": @"__ice_candidate", @"data": @{@"label": [NSNumber numberWithInteger:candidate.sdpMLineIndex], @"candidate": candidate.sdp, @"socketId": _currentId}};
    NSData *data = [NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:nil];
    [_socket send:data];
}

/** Called when a group of local Ice candidates have been removed. */
- (void)peerConnection:(RTCPeerConnection *)peerConnection
didRemoveIceCandidates:(NSArray<RTCIceCandidate *> *)candidates
{
    NSLog(@"%s",__func__);
}

/** New data channel has been opened. */
- (void)peerConnection:(RTCPeerConnection *)peerConnection
    didOpenDataChannel:(RTCDataChannel *)dataChannel
{
    NSLog(@"%s",__func__);
}

#pragma mark--SRWebSocketDelegate
- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message
{
    NSLog(@"收到服务器消息:%@",message);
    NSDictionary *dic = [NSJSONSerialization JSONObjectWithData:[message dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:nil];
    NSString *eventName = dic[@"eventName"];
    if ([eventName isEqualToString:@"_peers"])
    {
        NSDictionary *dataDic = dic[@"data"];
        NSArray *connections = dataDic[@"connections"];
        [_connectionIdArray addObjectsFromArray:connections];
        _myId = dataDic[@"you"];
        if (!_factory)
        {
            _factory = [[RTCPeerConnectionFactory alloc] init];
        }
        if (!_localStream)
        {
            [self createLocalStream];
        }
        [self createPeerConnections];
        [self addStreams];
        [self createOffers];
    }
    else if ([eventName isEqualToString:@"_ice_candidate"])
    {
        NSDictionary *dataDic = dic[@"data"];
        NSString *socketId = dataDic[@"socketId"];
        int sdpMLineIndex = [dataDic[@"label"] intValue];
        NSString *sdp = dataDic[@"candidate"];
        RTCIceCandidate *candidate = [[RTCIceCandidate alloc] initWithSdp:sdp sdpMLineIndex:sdpMLineIndex sdpMid:@""];
        RTCPeerConnection *peerConnection = [_connectionDic objectForKey:socketId];
        [peerConnection addIceCandidate:candidate];
    }
    else if ([eventName isEqualToString:@"_new_peer"])
    {
        NSDictionary *dataDic = dic[@"data"];
        NSString *socketId = dataDic[@"socketId"];
        RTCPeerConnection *peerConnection = [self createPeerConnection:socketId];
        if (!_localStream)
        {
            [self createLocalStream];
        }
        [peerConnection addStream:_localStream];
        [_connectionIdArray addObject:socketId];
        [_connectionDic setObject:peerConnection forKey:socketId];
    }
    else if ([eventName isEqualToString:@"_remove_peer"])
    {
        NSDictionary *dataDic = dic[@"data"];
        NSString *socketId = dataDic[@"socketId"];
        [self closePeerConnection:socketId];
    }
    else if ([eventName isEqualToString:@"_offer"])
    {
        NSDictionary *dataDic = dic[@"data"];
        NSDictionary *sdpDic = dataDic[@"sdp"];
        NSString *sdp = sdpDic[@"sdp"];
        NSString *type = sdpDic[@"type"];
        NSString *socketId = dataDic[@"socketId"];
        RTCPeerConnection *peerConnection = [_connectionDic objectForKey:socketId];
        RTCSessionDescription *remoteSdp = [[RTCSessionDescription alloc] initWithType:[type isEqualToString:@"offer"] ? RTCSdpTypeOffer : RTCSdpTypeAnswer sdp:sdp];
        RTCSessionDescription *newSdp = [self descriptionForDescription:remoteSdp preferredVideoCodec:@"H264"];
        __weak RTCPeerConnection * weakPeerConnection = peerConnection;
        [peerConnection setRemoteDescription:newSdp completionHandler:^(NSError * _Nullable error) {
            if (error)
            {
                NSLog(@"%@", error);
            }
            else
            {
                __weak RTCPeerConnection * weakPeerConnection2 = weakPeerConnection;
                [weakPeerConnection answerForConstraints:[self offerOranswerConstraint] completionHandler:^(RTCSessionDescription * _Nullable sdp, NSError * _Nullable error) {
                    if (error)
                    {
                        NSLog(@"%@",error);
                    }
                    else
                    {
                        __weak RTCPeerConnection * weakPeerConnection3 = weakPeerConnection2;
                        RTCSessionDescription *newSdp = [self descriptionForDescription:sdp preferredVideoCodec:@"H264"];
                        [weakPeerConnection2 setLocalDescription:newSdp completionHandler:^(NSError * _Nullable error) {
                            if (error)
                            {
                                NSLog(@"%@",error);
                            }
                            else
                            {
                                NSString *sdpString = weakPeerConnection3.localDescription.sdp;
                                NSDictionary *dic = @{@"eventName": @"__answer", @"data": @{@"sdp": @{@"type": @"answer", @"sdp": sdpString}, @"socketId": _currentId}};
                                NSData *data = [NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:nil];
                                [_socket send:data];
                            }
                        }];
                    }
                }];
            }
        }];
        _currentId = socketId;
        _role = RoleCallee;
    }
    else if ([eventName isEqualToString:@"_answer"])
    {
        NSDictionary *dataDic = dic[@"data"];
        NSDictionary *sdpDic = dataDic[@"sdp"];
        NSString *sdp = sdpDic[@"sdp"];
        NSString *type = sdpDic[@"type"];
        NSString *socketId = dataDic[@"socketId"];
        RTCPeerConnection *peerConnection = [_connectionDic objectForKey:socketId];
        RTCSessionDescription *remoteSdp = [[RTCSessionDescription alloc] initWithType:[type isEqualToString:@"offer"] ? RTCSdpTypeOffer : RTCSdpTypeAnswer sdp:sdp];
        RTCSessionDescription *newSdp = [self descriptionForDescription:remoteSdp preferredVideoCodec:@"H264"];
        [peerConnection setRemoteDescription:newSdp completionHandler:^(NSError * _Nullable error) {
            
        }];
    }
}
- (void)webSocketDidOpen:(SRWebSocket *)webSocket
{
    NSLog(@"websocket建立成功");
    [self joinRoom:_room];
}
- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error
{
    NSLog(@"%s",__func__);
    NSLog(@"%ld:%@",(long)error.code, error.localizedDescription);
//    [[[UIAlertView alloc] initWithTitle:@"提示" message:[NSString stringWithFormat:@"%ld:%@",(long)error.code, error.localizedDescription] delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil, nil] show];
}
- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean
{
    NSLog(@"%s",__func__);
    NSLog(@"%ld:%@",(long)code, reason);
//    [[[UIAlertView alloc] initWithTitle:@"提示" message:[NSString stringWithFormat:@"%ld:%@",(long)code, reason] delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil, nil] show];
}
@end
