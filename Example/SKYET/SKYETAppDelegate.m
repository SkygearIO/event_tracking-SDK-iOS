#import "SKYETAppDelegate.h"
#import "SKYETViewController.h"
#import "SKYETTracker.h"
#import <SKYKit/SKYKit.h>

@interface SKYETAppDelegate()

@property (strong, nonatomic) SKYETTracker *tracker;

@end

@implementation SKYETAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Override point for customization after application launch.
    SKYContainer *container = [SKYContainer defaultContainer];
    [container configAddress:@"http://192.168.1.127:3000/"];
    [container configureWithAPIKey:@"et"];
    _tracker = [[SKYETTracker alloc] initWithContainer:container];
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = [[SKYETViewController alloc] init];
    
    UIButton *button = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 200, 200)];
    button.backgroundColor = [UIColor redColor];
    [button setTitle:@"Hello" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(onClick) forControlEvents:UIControlEventTouchUpInside];
    [self.window.rootViewController.view addSubview:button];
    [self.window makeKeyAndVisible];
    return YES;
}

-(void)onClick
{
    NSLog(@"Clicked start");
    [_tracker track:@"Hello World" attributes:@{@"some_string": @"some_string", @"some_bool": @YES, @"some_int": @1, @"some_double": @1.0}];
    NSLog(@"Clicked end");
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@end
