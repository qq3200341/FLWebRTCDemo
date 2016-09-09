//
//  WebRTCHelper.h
//  WebRTCDemo
//
//  Created by qq3200341 on 16/8/12.
//  Copyright © 2016年 maipu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <SocketRocket.h>
#import "RTCMediaStream.h"
#import "RTCPeerConnectionFactory.h"
#import "RTCPeerConnection.h"
#import "RTCPair.h"
#import "RTCMediaConstraints.h"
#import "RTCAudioTrack.h"
#import "RTCVideoTrack.h"
#import "RTCVideoCapturer.h"
#import "RTCSessionDescription.h"
#import "RTCSessionDescriptionDelegate.h"
#import "RTCEAGLVideoView.h"
#import "RTCICEServer.h"
#import "RTCVideoSource.h"
#import "RTCAVFoundationVideoSource.h"
#import "RTCICECandidate.h"

@protocol WebRTCHelperDelegate;

@interface WebRTCHelper : NSObject<SRWebSocketDelegate>

@property (nonatomic, assign)id<WebRTCHelperDelegate> delegate;

/**
*  与服务器建立连接
*
*  @param server 服务器地址
*  @param room   房间号
*/
- (void)connectServer:(NSString *)server room:(NSString *)room;
/**
 *  退出房间
 */
- (void)exitRoom;
@end

@protocol WebRTCHelperDelegate <NSObject>

@optional
- (void)webRTCHelper:(WebRTCHelper *)webRTChelper setLocalStream:(RTCMediaStream *)stream userId:(NSString *)userId;
- (void)webRTCHelper:(WebRTCHelper *)webRTChelper addRemoteStream:(RTCMediaStream *)stream userId:(NSString *)userId;
- (void)webRTCHelper:(WebRTCHelper *)webRTChelper closeWithUserId:(NSString *)userId;
@end