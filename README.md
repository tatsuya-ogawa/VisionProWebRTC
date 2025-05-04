# VisionProWebRTC

A sample repository demonstrating WebRTC integration on Apple Vision Pro using Amazon Kinesis Video Streams.

## Features

- **Bundled libwebrtc for VisionOS**  
  Prebuilt WebRTC libraries targeting VisionOS are included out of the box.

- **Amazon Kinesis Video Streams WebRTC signaling**  
  Uses AWS Kinesis Video Streams WebRTC for session signaling and media exchange.

- **Partial reuse of iOS SDK**  
  Since the official KVS WebRTC SDK for iOS doesn’t build directly on VisionOS, this project reuses selected parts of the [awslabs/amazon-kinesis-video-streams-webrtc-sdk-ios](https://github.com/awslabs/amazon-kinesis-video-streams-webrtc-sdk-ios) repository.

- **Enterprise API support**  
  If you have Enterprise API entitlement on VisionOS, a custom WebRTC renderer is implemented for the Main Camera feed.

- **Placeholder configuration**  
  All AWS/Kinesis configuration values are placeholders. To run the sample, you must fill in your own settings in `amplifyconfiguration.json` and replace the `FIXME` markers in code.

- **Enterprise license file is not included**
  VisionPro enterprise liceense file is not included. So you must use your own license file.

## CodeSign
* if you need signing to WebRTC.framework
```
codesign --sign "Developer ID Application: Your Team Name (YOURTEAMID)" WebRTC.framework
```
