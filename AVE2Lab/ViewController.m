#import "ViewController.h"
#import <VideoToolbox/VideoToolbox.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>

@interface ViewController ()
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UIButton *runButton;
@property (nonatomic, assign) NSUInteger submittedFrames;
@property (nonatomic, assign) NSUInteger successfulCallbacks;
@property (nonatomic, assign) VTCompressionSessionRef compressionSession;
@property (nonatomic, assign) BOOL running;
@end

static void OutputCallback(void *refCon, void *sourceFrameRefCon,
                           OSStatus status, VTEncodeInfoFlags flags,
                           CMSampleBufferRef sampleBuffer) {
    ViewController *vc = (__bridge ViewController *)refCon;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (status == noErr && sampleBuffer != NULL) {
            vc.successfulCallbacks++;
        } else {
            [vc log:[NSString stringWithFormat:@"Encoder callback error: %d", (int)status]];
        }
    });
}

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"AVE2Lab";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.runButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.runButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.runButton setTitle:@"Run VideoToolbox Test" forState:UIControlStateNormal];
    self.runButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [self.runButton addTarget:self action:@selector(runTest) forControlEvents:UIControlEventTouchUpInside];

    self.logView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    self.logView.editable = NO;
    self.logView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.logView.backgroundColor = UIColor.secondarySystemBackgroundColor;

    [self.view addSubview:self.runButton];
    [self.view addSubview:self.logView];
    [NSLayoutConstraint activateConstraints:@[
        [self.runButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [self.runButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.runButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.runButton.heightAnchor constraintEqualToConstant:48],
        [self.logView.topAnchor constraintEqualToAnchor:self.runButton.bottomAnchor constant:12],
        [self.logView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.logView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [self.logView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12]
    ]];

    [self log:@"Ready. This is a normal video-encoding workload, not a vulnerability trigger."];
    [self log:[NSString stringWithFormat:@"iOS: %@", NSProcessInfo.processInfo.operatingSystemVersionString]];
}

- (void)log:(NSString *)message {
    NSString *text = [self.logView.text stringByAppendingFormat:@"%@\n", message];
    self.logView.text = text;
    [self.logView scrollRangeToVisible:NSMakeRange(text.length, 0)];
    NSLog(@"[AVE2Lab] %@", message);
}

- (void)runTest {
    if (self.running) return;
    self.running = YES;
    self.runButton.enabled = NO;
    self.submittedFrames = 0;
    self.successfulCallbacks = 0;
    [self log:@"Starting H.264 encode session (640x480, 60 frames)..."];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self performTest];
    });
}

- (void)performTest {
    const int width = 640, height = 480, count = 60;
    VTCompressionSessionRef session = NULL;

    OSStatus status = VTCompressionSessionCreate(
        kCFAllocatorDefault, width, height, kCMVideoCodecType_H264,
        NULL, NULL, NULL, OutputCallback, (__bridge void *)self, &session);

    if (status != noErr || session == NULL) {
        [self finish:[NSString stringWithFormat:@"Session creation failed: %d", (int)status]];
        return;
    }

    self.compressionSession = session;
    VTSessionSetProperty(session, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(session, kVTCompressionPropertyKey_ProfileLevel,
                          kVTProfileLevel_H264_Baseline_AutoLevel);

    status = VTCompressionSessionPrepareToEncodeFrames(session);
    if (status != noErr) {
        VTCompressionSessionInvalidate(session);
        CFRelease(session);
        self.compressionSession = NULL;
        [self finish:[NSString stringWithFormat:@"Prepare failed: %d", (int)status]];
        return;
    }

    for (int i = 0; i < count; i++) {
        CVPixelBufferRef pixel = NULL;
        NSDictionary *attrs = @{
            (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (NSString *)kCVPixelBufferWidthKey: @(width),
            (NSString *)kCVPixelBufferHeightKey: @(height),
            (NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
            (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
        };

        CVReturn cr = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                          kCVPixelFormatType_32BGRA,
                                          (__bridge CFDictionaryRef)attrs, &pixel);
        if (cr != kCVReturnSuccess || pixel == NULL) {
            [self finish:[NSString stringWithFormat:@"Pixel buffer failed: %d", (int)cr]];
            break;
        }

        CVPixelBufferLockBaseAddress(pixel, 0);
        uint8_t *base = CVPixelBufferGetBaseAddress(pixel);
        size_t stride = CVPixelBufferGetBytesPerRow(pixel);
        for (int y = 0; y < height; y++) {
            uint8_t *row = base + y * stride;
            for (int x = 0; x < width; x++) {
                size_t p = (size_t)x * 4;
                row[p] = (uint8_t)(x + i);
                row[p + 1] = (uint8_t)(y + i);
                row[p + 2] = (uint8_t)(x + y);
                row[p + 3] = 255;
            }
        }
        CVPixelBufferUnlockBaseAddress(pixel, 0);

        CMTime pts = CMTimeMake(i, 30);
        VTEncodeInfoFlags flags = 0;
        status = VTCompressionSessionEncodeFrame(session, pixel, pts,
                                                 kCMTimeInvalid, NULL, NULL, &flags);
        CVPixelBufferRelease(pixel);

        if (status != noErr) {
            [self finish:[NSString stringWithFormat:@"Frame %d failed: %d", i, (int)status]];
            VTCompressionSessionInvalidate(session);
            CFRelease(session);
            self.compressionSession = NULL;
            return;
        }
        self.submittedFrames++;
    }

    OSStatus endStatus = VTCompressionSessionCompleteFrames(session, kCMTimeInvalid);
    VTCompressionSessionInvalidate(session);
    CFRelease(session);
    self.compressionSession = NULL;
    [self finish:[NSString stringWithFormat:@"Test completed. Frames submitted: %lu/%d. Completion status: %d.",
                  (unsigned long)self.submittedFrames, count, (int)endStatus]];
}

- (void)finish:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self log:message];
        [self log:[NSString stringWithFormat:@"Successful encoded-output callbacks: %lu",
                   (unsigned long)self.successfulCallbacks]];
        self.running = NO;
        self.runButton.enabled = YES;
    });
}

@end
