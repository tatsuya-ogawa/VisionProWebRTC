//
//  WebRTCView.swift
//  VisionProHello
//
//  Created by Tatsuya Ogawa on 2024/10/26.
//

import SwiftUI
import RealityKit
import WebRTC
protocol RTCRemoteVideoRendererDelegate{
    func setRemoteRTCVideoRenderer(_ renderer:RTCVideoRenderer)
}
protocol RTCLocalVideoRendererDelegate{
    func setLocalRTCVideoRenderer(_ renderer:RTCVideoRenderer)
}
@Observable
class WebRTCViewModel{
    // FIXME
    var channelName = "PLACE_YOUR_CHANNEL"
    var isMaster:Bool = false
    var localSenderId:String = ""
    var remoteSenderClientId:String?
    weak var remoteRTCVideoRenderer:RTCVideoRenderer?
    weak var localRTCVideoRenderer:RTCVideoRenderer?
    let manager :AwsSignalingClientManager = .init()
    var webRTCClient:WebRTCClient? = nil
    var signalingClient:SignalingClient? = nil
    init(){
        let localSenderId = NSUUID().uuidString.lowercased()
        let isMaster = false
        self.localSenderId = localSenderId
        self.isMaster = isMaster
        self.manager.localSenderId = localSenderId
        self.manager.channelName = channelName
        self.manager.isMaster = isMaster
        self.manager.channelRole = isMaster ? .master: .viewer
    }
    func start()async{
        do{
            let wsUrl = try await manager.getSignedWSSUrl()
            let iceCandidate = try await manager.getIceCandidate()
            self.signalingClient = SignalingClient(serverUrl: wsUrl!)
            self.webRTCClient = WebRTCClient(iceServers:iceCandidate, isAudioOn: false,isMicrophoneOn: false)
            self.signalingClient?.delegate = self
            self.webRTCClient?.delegate = self
            if let remoteRTCVideoRenderer = self.remoteRTCVideoRenderer{
                self.webRTCClient?.renderRemoteVideo(to: remoteRTCVideoRenderer)
            }
            if let localRTCVideoRenderer = self.localRTCVideoRenderer{
                self.webRTCClient?.renderLocalVideo(to: localRTCVideoRenderer)
            }
            self.signalingClient?.connect()
        }catch{
            
        }
    }
    func startLocalVideoCapture()async{
        await self.webRTCClient?.startCapture()
    }
}
extension WebRTCViewModel:SignalClientDelegate{
    func signalClient(_ signalClient: SignalingClient, senderClientId: String, didReceiveRemoteSdp sdp: RTCSessionDescription) {
        self.remoteSenderClientId = senderClientId
        webRTCClient?.set(remoteSdp: sdp,clientId: senderClientId){_ in
            Task{
                self.webRTCClient?.answer { localSdp in
                    Task{
                        await self.signalingClient?.sendAnswer(rtcSdp: localSdp, recipientClientId: senderClientId)
                        self.webRTCClient?.updatePeerConnectionAndHandleIceCandidates(clientId: senderClientId)
                    }
                }
            }
        }
    }
    
    func signalClient(_ signalClient: SignalingClient, senderClientId: String, didReceiveCandidate candidate: RTCIceCandidate) {
        self.remoteSenderClientId = senderClientId
        webRTCClient!.set(remoteCandidate: candidate, clientId: senderClientId)
    }
}
extension WebRTCViewModel:WebRTCClientDelegate{
    func webRTCClient(_ client: WebRTCClient, didGenerate candidate: RTCIceCandidate) {
        Task{
            await signalingClient?.sendIceCandidate(rtcIceCandidate: candidate, master: isMaster,
                                              recipientClientId: remoteSenderClientId ??  "ConsumerViewer",
                                              senderClientId: localSenderId)
        }
    }
    
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState) {
        switch state {
        case .connected, .completed:
            print("WebRTC connected/completed state")
        case .disconnected:
            print("WebRTC disconnected state")
        case .new:
            print("WebRTC new state")
        case .checking:
            print("WebRTC checking state")
        case .failed:
            print("WebRTC failed state")
        case .closed:
            print("WebRTC closed state")
        case .count:
            print("WebRTC count state")
        @unknown default:
            print("WebRTC unknown state")
        }
    }
    
    func webRTCClient(_ client: WebRTCClient, didReceiveData data: Data) {
    }
    
    func signalClientDidConnect(_ signalClient: SignalingClient) {
        if(!self.isMaster){
            webRTCClient?.offer { sdp in
                Task{
                    await self.signalingClient?.sendOffer(rtcSdp: sdp, senderClientid: self.localSenderId)
                }
            }
        }
    }
    
    func signalClientDidDisconnect(_ signalClient: SignalingClient) {
    }
}
extension WebRTCViewModel:RTCRemoteVideoRendererDelegate{
    func setRemoteRTCVideoRenderer(_ renderer: any RTCVideoRenderer) {
        self.remoteRTCVideoRenderer = renderer
    }
}
extension WebRTCViewModel:RTCLocalVideoRendererDelegate{
    func setLocalRTCVideoRenderer(_ renderer: any RTCVideoRenderer) {
        self.localRTCVideoRenderer = renderer
    }
}

struct WebRTCView: View {
//    @ObservedObject var WebRTCViewModel:WebRTCViewModel = .init()
    @Environment(WebRTCViewModel.self) private var webRTCViewModel
    var body: some View {
        VStack {
//            Model3D(named: "Scene", bundle: realityKitContentBundle)
//                .padding(.bottom, 50)
            LocalView(delegate: webRTCViewModel)
            RemoteView(delegate: webRTCViewModel)
            Text("\(webRTCViewModel.remoteSenderClientId)")
          
        }
        .padding()
        .onAppear{
            Task{
                await webRTCViewModel.start()
            }
        }
    }
}

struct RemoteView: UIViewRepresentable {
    typealias UIViewType = RTCMTLVideoView
    
    var delegate: RTCRemoteVideoRendererDelegate?
    
    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720))
        view.backgroundColor = .red
        view.videoContentMode = .scaleAspectFill
        delegate?.setRemoteRTCVideoRenderer(view)
        return view
    }
    
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
    }
}
struct LocalView: UIViewRepresentable {
    typealias UIViewType = RTCMTLVideoView
    
    var delegate: RTCLocalVideoRendererDelegate?
    
    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720))
        view.backgroundColor = .blue
        view.videoContentMode = .scaleAspectFill
        delegate?.setLocalRTCVideoRenderer(view)
        return view
    }
    
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
    }
}

#Preview(windowStyle: .automatic) {
    WebRTCView()
}
