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

@interface WebRTCHelper ()<RTCPeerConnectionDelegate, RTCSessionDescriptionDelegate>

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
    _localStream = [_factory mediaStreamWithLabel:@"ARDAMS"];
    //音频
    RTCAudioTrack *audioTrack = [_factory audioTrackWithID:@"ARDAMSa0"];
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
            RTCVideoCapturer *capturer = [RTCVideoCapturer capturerWithDeviceName:device.localizedName];
            RTCVideoSource *videoSource = [_factory videoSourceWithCapturer:capturer constraints:[self localVideoConstraints]];
            RTCVideoTrack *videoTrack = [_factory videoTrackWithID:@"ARDAMSv0" source:videoSource];
            
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
    RTCPair *maxWidth = [[RTCPair alloc] initWithKey:@"maxWidth" value:@"640"];
    RTCPair *minWidth = [[RTCPair alloc] initWithKey:@"minWidth" value:@"640"];
    
    RTCPair *maxHeight = [[RTCPair alloc] initWithKey:@"maxHeight" value:@"480"];
    RTCPair *minHeight = [[RTCPair alloc] initWithKey:@"minHeight" value:@"480"];
    
    RTCPair *minFrameRate = [[RTCPair alloc] initWithKey:@"minFrameRate" value:@"15"];
    
    NSArray *mandatory = @[maxWidth, minWidth, maxHeight, minHeight, minFrameRate];
    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:mandatory optionalConstraints:nil];
    return constraints;
}
/**
 *  为所有连接创建offer
 */
- (void)createOffers
{
    [_connectionDic enumerateKeysAndObjectsUsingBlock:^(NSString *key, RTCPeerConnection *obj, BOOL * _Nonnull stop) {
        _currentId = key;
        _role = RoleCaller;
        [obj createOfferWithDelegate:self constraints:[self offerOranswerConstraint]];
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
        [RTCPeerConnectionFactory initializeSSL];
        _factory = [[RTCPeerConnectionFactory alloc] init];
    }
    RTCPeerConnection *connection = [_factory peerConnectionWithICEServers:nil constraints:[self peerConnectionConstraints] delegate:self];
    return connection;
}
/**
 *  peerConnection约束
 *
 *  @return <#return value description#>
 */
- (RTCMediaConstraints *)peerConnectionConstraints
{
    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:nil optionalConstraints:@[[[RTCPair alloc] initWithKey:@"DtlsSrtpKeyAgreement" value:@"true"]]];
    return constraints;
}
/**
 *  设置offer/answer的约束
 */
- (RTCMediaConstraints *)offerOranswerConstraint
{
    NSMutableArray *array = [NSMutableArray array];
    RTCPair *receiveAudio = [[RTCPair alloc] initWithKey:@"OfferToReceiveAudio" value:@"true"];
    [array addObject:receiveAudio];
    
    NSString *video = @"true";
    RTCPair *receiveVideo = [[RTCPair alloc] initWithKey:@"OfferToReceiveVideo" value:video];
    [array addObject:receiveVideo];
    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:array optionalConstraints:nil];
    return constraints;
}

#pragma mark--RTCSessionDescriptionDelegate
// Called when creating a session.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
didCreateSessionDescription:(RTCSessionDescription *)sdp
                 error:(NSError *)error
{
    NSLog(@"%s",__func__);
    [peerConnection setLocalDescriptionWithDelegate:self sessionDescription:sdp];
}

// Called when setting a local or remote description.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
didSetSessionDescriptionWithError:(NSError *)error
{
    NSLog(@"%s",__func__);
    if (peerConnection.signalingState == RTCSignalingHaveRemoteOffer)
    {
        [peerConnection createAnswerWithDelegate:self constraints:[self offerOranswerConstraint]];
    }
    else if (peerConnection.signalingState == RTCSignalingHaveLocalOffer)
    {
        if (_role == RoleCallee)
        {
            NSDictionary *dic = @{@"eventName": @"__answer", @"data": @{@"sdp": @{@"type": @"answer", @"sdp": peerConnection.localDescription.description}, @"socketId": _currentId}};
            NSData *data = [NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:nil];
            [_socket send:data];
        }
        else if(_role == RoleCaller)
        {
            NSDictionary *dic = @{@"eventName": @"__offer", @"data": @{@"sdp": @{@"type": @"offer", @"sdp": peerConnection.localDescription.description}, @"socketId": _currentId}};
            NSData *data = [NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:nil];
            [_socket send:data];
        }
    }
    else if (peerConnection.signalingState == RTCSignalingStable)
    {
        if (_role == RoleCallee)
        {
            NSDictionary *dic = @{@"eventName": @"__answer", @"data": @{@"sdp": @{@"type": @"answer", @"sdp": peerConnection.localDescription.description}, @"socketId": _currentId}};
            NSData *data = [NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:nil];
            [_socket send:data];
        }
    }
}
#pragma mark--RTCPeerConnectionDelegate
// Triggered when the SignalingState changed.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
 signalingStateChanged:(RTCSignalingState)stateChanged
{
    NSLog(@"%s",__func__);
    NSLog(@"%d", stateChanged);
}

// Triggered when media is received on a new stream from remote peer.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
           addedStream:(RTCMediaStream *)stream
{
    NSLog(@"%s",__func__);
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([_delegate respondsToSelector:@selector(webRTCHelper:addRemoteStream:userId:)])
        {
            [_delegate webRTCHelper:self addRemoteStream:stream userId:_currentId];
        }
    });
}

// Triggered when a remote peer close a stream.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
         removedStream:(RTCMediaStream *)stream
{
    NSLog(@"%s",__func__);
}

// Triggered when renegotiation is needed, for example the ICE has restarted.
- (void)peerConnectionOnRenegotiationNeeded:(RTCPeerConnection *)peerConnection
{
    NSLog(@"%s",__func__);
}

// Called any time the ICEConnectionState changes.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
  iceConnectionChanged:(RTCICEConnectionState)newState
{
    NSLog(@"%s",__func__);
    NSLog(@"%d", newState);
}

// Called any time the ICEGatheringState changes.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
   iceGatheringChanged:(RTCICEGatheringState)newState
{
    NSLog(@"%s",__func__);
    NSLog(@"%d", newState);
}

// New Ice candidate have been found.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
       gotICECandidate:(RTCICECandidate *)candidate
{
    NSLog(@"%s",__func__);
    NSDictionary *dic = @{@"eventName": @"__ice_candidate", @"data": @{@"label": [NSNumber numberWithInteger:candidate.sdpMLineIndex], @"candidate": candidate.sdp, @"socketId": _currentId}};
    NSData *data = [NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:nil];
    [_socket send:data];
}

// New data channel has been opened.
- (void)peerConnection:(RTCPeerConnection*)peerConnection didOpenDataChannel:(RTCDataChannel*)dataChannel

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
            [RTCPeerConnectionFactory initializeSSL];
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
        NSInteger sdpMLineIndex = [dataDic[@"label"] integerValue];
        NSString *sdp = dataDic[@"candidate"];
        RTCICECandidate *candidate = [[RTCICECandidate alloc] initWithMid:nil index:sdpMLineIndex sdp:sdp];
        RTCPeerConnection *peerConnection = [_connectionDic objectForKey:socketId];
        [peerConnection addICECandidate:candidate];
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
        RTCSessionDescription *remoteSdp = [[RTCSessionDescription alloc] initWithType:type sdp:sdp];
        [peerConnection setRemoteDescriptionWithDelegate:self sessionDescription:remoteSdp];
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
        RTCSessionDescription *remoteSdp = [[RTCSessionDescription alloc] initWithType:type sdp:sdp];
        [peerConnection setRemoteDescriptionWithDelegate:self sessionDescription:remoteSdp];
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
