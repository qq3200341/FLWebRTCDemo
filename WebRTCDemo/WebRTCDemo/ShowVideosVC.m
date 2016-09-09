//
//  ShowVideosVC.m
//  WebRTCDemo
//
//  Created by qq3200341 on 16/9/6.
//  Copyright © 2016年 maipu. All rights reserved.
//

#import "ShowVideosVC.h"
#import "WebRTCHelper.h"

@interface ShowVideosVC ()<UICollectionViewDelegate, UICollectionViewDataSource, WebRTCHelperDelegate>

@property (nonatomic, strong)WebRTCHelper *webRTCHelper;
@property (weak, nonatomic) IBOutlet UICollectionView *myCollectionView;
@property (nonatomic, strong)NSMutableArray *videoTrackArray;
@property (nonatomic,strong)NSMutableArray *userIdArray;

@end

@implementation ShowVideosVC

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [_webRTCHelper exitRoom];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _videoTrackArray = [NSMutableArray array];
    _userIdArray = [NSMutableArray array];
    [_myCollectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"cell"];
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 10;
    layout.minimumInteritemSpacing = 10;
    layout.itemSize = CGSizeMake(80, 80);
    layout.sectionInset = UIEdgeInsetsMake(10, 10, 10, 10);
    _myCollectionView.collectionViewLayout = layout;
    
    _webRTCHelper = [[WebRTCHelper alloc] init];
    _webRTCHelper.delegate = self;
    [_webRTCHelper connectServer:_server room:_room];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark--UICollectionViewDataSource
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return _userIdArray.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"cell" forIndexPath:indexPath];
    RTCVideoTrack *track = _videoTrackArray[indexPath.row];
    RTCEAGLVideoView *view = [[RTCEAGLVideoView alloc] initWithFrame:CGRectMake(0, 0, 80, 80)];
    [cell.contentView addSubview:view];
    [track addRenderer:view];
    return cell;
}

#pragma mark--WebRTCHelperDelegate
- (void)webRTCHelper:(WebRTCHelper *)webRTChelper setLocalStream:(RTCMediaStream *)stream userId:(NSString *)userId
{
    if (stream)
    {
        RTCVideoTrack *track = [stream.videoTracks lastObject];
        [_videoTrackArray addObject:track];
        [_userIdArray addObject:userId];
        [_myCollectionView reloadData];
    }
}

- (void)webRTCHelper:(WebRTCHelper *)webRTChelper addRemoteStream:(RTCMediaStream *)stream userId:(NSString *)userId
{
    RTCVideoTrack *track = [stream.videoTracks lastObject];
    [_videoTrackArray addObject:track];
    [_userIdArray addObject:userId];
    [_myCollectionView reloadData];
}

- (void)webRTCHelper:(WebRTCHelper *)webRTChelper closeWithUserId:(NSString *)userId
{
    NSInteger index = [_userIdArray indexOfObject:userId];
    [_userIdArray removeObjectAtIndex:index];
    [_videoTrackArray removeObjectAtIndex:index];
    [_myCollectionView reloadData];
}
@end
