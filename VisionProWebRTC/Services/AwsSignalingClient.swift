import Amplify
import Foundation
import AWSCognitoAuthPlugin
import AWSPluginsCore
import AWSSDKIdentity
import AWSKinesisVideo
import AWSKinesisVideoSignaling
import WebRTC
class AuthManager {
    init() {
        configureAmplify()
    }

    private func configureAmplify() {
        do {
            try Amplify.add(plugin: AWSCognitoAuthPlugin())
            try Amplify.configure()
            print("Amplify configured with Auth plugin")
        } catch {
            print("Failed to initialize Amplify: \(error)")
        }
    }

    func getAWSCredentials(username: String, password: String) async throws -> AuthAWSCognitoCredentials {
        if try await !isSignedIn() {
            try await signIn(username: username, password: password)
        }
        return try await fetchCredentials()
    }

    private func isSignedIn() async throws -> Bool {
        let session = try await Amplify.Auth.fetchAuthSession()
        return session.isSignedIn
    }

    private func signIn(username: String, password: String) async throws {
        let signInResult = try await Amplify.Auth.signIn(username: username, password: password)
        guard signInResult.isSignedIn else {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "サインイン中に問題が発生しました"])
        }
    }

    private func fetchCredentials() async throws -> AuthAWSCognitoCredentials {
        let session = try await Amplify.Auth.fetchAuthSession()

        // Get identity id
        if let identityProvider = session as? AuthCognitoIdentityProvider {
            let identityId = try identityProvider.getIdentityId().get()
            print("Identity id \(identityId)")
        }

        // Get AWS credentials
        guard let awsCredentialsProvider = session as? AuthAWSCredentialsProvider else{
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid credentials provider"])
        }
        let credentials = try awsCredentialsProvider.getAWSCredentials().get()
        guard let cognitoCredentials = credentials as? AuthAWSCognitoCredentials else {
            throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid credentials"])
        }
        // Do something with the credentials
        return cognitoCredentials
    }
}
class AwsSignalingClientManager{
    let authManager = AuthManager()
    // FIXME
    let region = "PLACE_YOUR_COGNITO_REGION_HERE"
    let username = "PLACE_YOUR_COGNITO_USERNAME_HERE"
    let password = "PLACE_YOUR_COGNITO_PASSWORD_HERE"
    var localSenderId:String = ""
    var channelName:String = ""
    var isMaster:Bool = false
    var channelRole :KinesisVideoClientTypes.ChannelRole = .viewer
    func getCredentials()async throws -> AuthAWSCognitoCredentials{
        let credentials = try await self.authManager.getAWSCredentials(username:  username, password: password)
        return credentials
    }
    // Get list of Ice Server Config
    func getIceCandidate()async throws-> [RTCIceServer]{
        let credentials : AuthAWSCognitoCredentials = try await self.getCredentials()
        let identity : AWSCredentialIdentity = AWSCredentialIdentity(accessKey: credentials.accessKeyId, secret: credentials.secretAccessKey,sessionToken: credentials.sessionToken)
        let channelARN = try await self.getChannelARN(credentials: credentials, channelName: channelName)
        let endpoints = try await self.getEndpoint(credentials: credentials,channelARN: channelARN!)
        var httpsEndpoint = ""
        for endpoint in endpoints.resourceEndpointList! {
            switch endpoint.protocol {
            case .https:
                httpsEndpoint = endpoint.resourceEndpoint!
                break
            case .wss:
                break
            case .webrtc:
                break
            case .none:
                break
            case .some(.sdkUnknown(_)):
                break
            }
        }
        
        let config = try! await KinesisVideoSignalingClient.Config(region: self.region)
        config.endpoint = httpsEndpoint
        config.awsCredentialIdentityResolver = try! StaticAWSCredentialIdentityResolver(identity)
        let kinesisVideoSignalingClient: KinesisVideoSignalingClient =  KinesisVideoSignalingClient(config: config)
        var input = GetIceServerConfigInput()
        input.channelARN = channelARN!
        input.service = .turn
        input.clientId = self.localSenderId
        let candidate = try await kinesisVideoSignalingClient.getIceServerConfig(input: input)
        return (candidate.iceServerList?.map{iceServers in
            return RTCIceServer.init(urlStrings: iceServers.uris!, username: iceServers.username, credential: iceServers.password)
        } ?? []) + [RTCIceServer.init(urlStrings: ["stun:stun.kinesisvideo." + self.region + ".amazonaws.com:443"])]
    }
    func getEndpoint(credentials:AuthAWSCognitoCredentials,channelARN:String)async throws-> GetSignalingChannelEndpointOutput{
        let identity : AWSCredentialIdentity = AWSCredentialIdentity(accessKey: credentials.accessKeyId, secret: credentials.secretAccessKey,sessionToken: credentials.sessionToken)
        let config = try! await KinesisVideoClient.Config(region: self.region)
        config.awsCredentialIdentityResolver = try! StaticAWSCredentialIdentityResolver(identity)
        let kinesisVideoClient: KinesisVideoClient = KinesisVideoClient(config: config)
        var input = GetSignalingChannelEndpointInput()
        input.channelARN = channelARN
        input.singleMasterChannelEndpointConfiguration = KinesisVideoClientTypes.SingleMasterChannelEndpointConfiguration(protocols:[.wss,.https],role: self.channelRole)
        return try await kinesisVideoClient.getSignalingChannelEndpoint(input: input)
    }
    func getChannelARN(credentials:AuthAWSCognitoCredentials,channelName:String)async throws-> String? {
        let identity : AWSCredentialIdentity = AWSCredentialIdentity(accessKey: credentials.accessKeyId, secret: credentials.secretAccessKey,sessionToken: credentials.sessionToken)
        let config = try await KinesisVideoClient.Config(region: self.region)
        config.awsCredentialIdentityResolver = try StaticAWSCredentialIdentityResolver(identity)
        let kinesisVideoClient: KinesisVideoClient = KinesisVideoClient(config: config)
        var input = DescribeSignalingChannelInput()
        input.channelName = channelName
        let output = try await kinesisVideoClient.describeSignalingChannel(input: input)
        return output.channelInfo?.channelARN
    }
    func createSignedWSSUrl(credentials:AuthAWSCognitoCredentials, localSenderId:String,channelARN: String, region: String, wssEndpoint: String?, isMaster: Bool) -> URL? {
        // get AWS credentials to sign WSS Url with
        var httpURlString = wssEndpoint!
            + "?X-Amz-ChannelARN=" + channelARN
        if !isMaster {
            httpURlString += "&X-Amz-ClientId=" + localSenderId
        }
        let httpRequestURL = URL(string: httpURlString)
        let wssRequestURL = URL(string: wssEndpoint!)
        let wssURL = KVSSigner
            .sign(signRequest: httpRequestURL!,
                  secretKey: credentials.secretAccessKey,
                  accessKey: credentials.accessKeyId,
                  sessionToken: credentials.sessionToken,
                  wssRequest: wssRequestURL!,
                  region: region)
        return wssURL
    }
    func getSignedWSSUrl() async throws-> URL?{
        let credentials = try await self.getCredentials()
        let channelARN = try await self.getChannelARN(credentials: credentials, channelName: channelName)
        let endpoints = try await self.getEndpoint(credentials: credentials,channelARN: channelARN!)
        var wssEndpoint = ""
        for endpoint in endpoints.resourceEndpointList! {
            switch endpoint.protocol {
            case .https:
                break
            case .wss:
                wssEndpoint = endpoint.resourceEndpoint!
            case .webrtc:
                break
            case .none:
                break
            case .some(.sdkUnknown(_)):
                break
            }
        }
        let wssUrl = self.createSignedWSSUrl(credentials: credentials, localSenderId:localSenderId , channelARN: channelARN!, region: self.region, wssEndpoint:wssEndpoint, isMaster: self.isMaster)
        return wssUrl
    }
}
