//
//  ViewController.m
//  WebRTCDemo
//
//  Created by qq3200341 on 16/8/5.
//  Copyright © 2016年 maipu. All rights reserved.
//

#import "ViewController.h"
#import "WebRTCHelper.h"
#import "ShowVideosVC.h"

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UITextField *serverTf;
@property (weak, nonatomic) IBOutlet UITextField *roomTf;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark--点击
- (IBAction)joinRoom:(UIButton *)sender
{
    NSLog(@"加入房间");
    ShowVideosVC *svc = [[ShowVideosVC alloc] init];
    svc.server = _serverTf.text;
    svc.room = _roomTf.text;
    [self.navigationController pushViewController:svc animated:YES];
}

@end
