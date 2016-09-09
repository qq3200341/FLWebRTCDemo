# FLWebRTCDemo
基于webRTC的音视频通话，服务端采用开源项目SkyRTC，未实现stunserver和turnserver服务器，因此NAT环境下不可使用。

##如何运行
1、下载安装服务器：[SkyRTC项目](https://github.com/LingyuCoder/SkyRTC)，安装过程具体到SkyRTC-demo查看。
2、运行app，Server填写服务器对应ip，房间随意填写。
3、浏览器ip:3000#roomName，房间名与上面一致。
##使用
创建连接并进入房间：
````objc
- (void)connectServer:(NSString *)server room:(NSString *)room
````
退出房间：
````objc
- (void)exitRoom
````
