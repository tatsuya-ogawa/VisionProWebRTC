import Foundation
import WebRTC

// interface for remote connectivity events
protocol SignalClientDelegate {
    func signalClientDidConnect(_ signalClient: SignalingClient)
    func signalClientDidDisconnect(_ signalClient: SignalingClient)
    func signalClient(_ signalClient: SignalingClient, senderClientId: String, didReceiveRemoteSdp sdp: RTCSessionDescription)
    func signalClient(_ signalClient: SignalingClient, senderClientId: String, didReceiveCandidate candidate: RTCIceCandidate)
}

final class SignalingClient {
    private let socket: WebSocketProvider
    private let encoder = JSONEncoder()
    var delegate: SignalClientDelegate?

    init(serverUrl: URL) {
        socket = StarscreamWebSocket(url: serverUrl)
    }

    func connect() {
        socket.delegate = self
        socket.connect()
    }

    func disconnect() {
        socket.disconnect()
    }

    func sendOffer(rtcSdp: RTCSessionDescription, senderClientid: String) async{
        do {
            debugPrint("Sending SDP offer \(rtcSdp)")
            let message: Message = Message.createOfferMessage(sdp: rtcSdp.sdp, senderClientId: senderClientid)
            let data = try encoder.encode(message)
            let msg = String(data: data, encoding: .utf8)!
            try await socket.write(string: msg)
            print("Sent SDP offer message over to signaling:", msg)
        } catch {
            print(error)
        }
    }

    func sendAnswer(rtcSdp: RTCSessionDescription, recipientClientId: String) async{
        do {
            debugPrint("Sending SDP answer\(rtcSdp)")
            let message: Message = Message.createAnswerMessage(sdp: rtcSdp.sdp, recipientClientId)
            let data = try encoder.encode(message)
            let msg = String(data: data, encoding: .utf8)!
            try await socket.write(string: msg)
            print("Sent SDP answer message over to signaling:", msg)
        } catch {
            print(error)
        }
    }

    func sendIceCandidate(rtcIceCandidate: RTCIceCandidate, master: Bool,
                          recipientClientId: String,
                          senderClientId: String) async{
        do {
            debugPrint("Sending ICE candidate \(rtcIceCandidate)")
            let message: Message = Message.createIceCandidateMessage(candidate: rtcIceCandidate,
                                                                     master,
                                                                     recipientClientId: recipientClientId,
                                                                     senderClientId: senderClientId)
            let data = try encoder.encode(message)
            let msg = String(data: data, encoding: .utf8)!
            try await socket.write(string: msg)
            print("Sent ICE candidate message over to signaling:", msg)
        } catch {
            print(error)
        }
    }
}

// MARK: Websocket
extension SignalingClient: WebSocketProviderDelegate {
    func webSocketDidConnect(_ webSocket: any WebSocketProvider) {
        delegate?.signalClientDidConnect(self)
    }
    
    func webSocketDidDisconnect(_ webSocket: any WebSocketProvider) {
        delegate?.signalClientDidDisconnect(self)
    }
    
    func webSocket(_ webSocket: any WebSocketProvider, didReceiveData data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        var parsedMessage: Message?

        parsedMessage = Event.parseEvent(event: text)

        if parsedMessage != nil {
            let messagePayload = parsedMessage?.getMessagePayload()

            let messageType = parsedMessage?.getAction()
            let senderClientId = parsedMessage?.getSenderClientId()
            // todo: add a guard here because some of java base64 encode options might break ios base64 decode unless extended
            let message: String = String(messagePayload!.base64Decoded()!)

            do {
                let jsonObject = try message.trim().convertToDictionary()
                if jsonObject.count != 0 {
                    if messageType == "SDP_OFFER" {
                        guard let sdp = jsonObject["sdp"] as? String else {
                            return
                        }
                        let rcSessionDescription: RTCSessionDescription = RTCSessionDescription(type: .offer, sdp: sdp)
                        delegate?.signalClient(self, senderClientId: senderClientId!, didReceiveRemoteSdp: rcSessionDescription)
                        debugPrint("SDP offer received from signaling \(sdp)")
                    } else if messageType == "SDP_ANSWER" {
                        guard let sdp = jsonObject["sdp"] as? String else {
                            return
                        }
                        let rcSessionDescription: RTCSessionDescription = RTCSessionDescription(type: .answer, sdp: sdp)
                        delegate?.signalClient(self, senderClientId: "", didReceiveRemoteSdp: rcSessionDescription)
                        debugPrint("SDP answer received from signaling \(sdp)")
                    } else if messageType == "ICE_CANDIDATE" {
                        guard let iceCandidate = jsonObject["candidate"] as? String else {
                            return
                        }
                        guard let sdpMid = jsonObject["sdpMid"] as? String else {
                            return
                        }
                        guard let sdpMLineIndex = jsonObject["sdpMLineIndex"] as? Int32 else {
                            return
                        }
                        let rtcIceCandidate: RTCIceCandidate = RTCIceCandidate(sdp: iceCandidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
                        delegate?.signalClient(self, senderClientId: senderClientId!, didReceiveCandidate: rtcIceCandidate)
                        debugPrint("ICE candidate received from signaling \(iceCandidate)")
                    }
                } else {
                    dump(jsonObject)
                }
            } catch {
                print("payLoad parsing Error \(error)")
            }
        }
    }
}

extension String {
    func convertToDictionary() throws -> [String: Any] {
        let data = Data(utf8)

        if let anyResult = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            return anyResult
        } else {
            return [:]
        }
    }
}
