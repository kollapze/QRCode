//
//  QRCode+VideoDetector.swift
//
//  Copyright © 2022 Darren Ford. All rights reserved.
//
//  MIT license
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
//  documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
//  permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all copies or substantial
//  portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
//  WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
//  OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
//  OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#if os(iOS) || os(macOS)

import AVFoundation
import CoreImage

@available(macOS 10.11, iOS 4, macCatalyst 14.0, *)
public extension QRCode {

	/// A very basic qr code detector object for detecting qr codes in a video stream
	class VideoDetector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
		/// Errors generated by the video detector
		public enum CaptureError: Error {
			case noSession
			case noDefaultVideoDevice
			case cannotCreateVideoInput
			case cannotAddVideoOutput
		}

		/// The format for the callback block when a QR code is detected in the input stream
		public typealias DetectionBlock = (CIImage, [CIQRCodeFeature]) -> Void

		/// Start detecting qr codes in a video stream
		/// - Parameters:
		///   - queue: The queue to process results on. Defaults to `.global`
		///   - inputDevice: the capture input device, or nil to use the system's default video input device
		///   - detectionBlock: Called when qr code(s) are detected in the input video stream
		public func startDetecting(
			queue: DispatchQueue = .global(),
			inputDevice: AVCaptureDeviceInput? = nil,
			_ detectionBlock: @escaping DetectionBlock
		) throws {
			self.detectionBlock = detectionBlock

			var device = inputDevice
			if device == nil {
				guard let defaultVideo = AVCaptureDevice.default(for: AVMediaType.video) else {
					throw CaptureError.noDefaultVideoDevice
				}
				device = try AVCaptureDeviceInput(device: defaultVideo)
			}

			guard let device = device else { throw CaptureError.cannotCreateVideoInput }

			// Create a capture session
			let session = AVCaptureSession()
			session.addInput(device)

			// Create a video output
			let output = AVCaptureVideoDataOutput()
			guard session.canAddOutput(output) else {
				throw CaptureError.cannotAddVideoOutput
			}

			output.alwaysDiscardsLateVideoFrames = true
			output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
			output.setSampleBufferDelegate(self, queue: queue)
			session.addOutput(output)

			// Create the QRCode detector
			self.detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: nil)

			self.captureSession = session

			session.startRunning()
		}

		/// Returns a `AVCaptureVideoPreviewLayer` which reflects the content of the current capture session
		public func makePreviewLayer() throws -> AVCaptureVideoPreviewLayer {
			guard let session = self.captureSession else {
				throw CaptureError.noSession
			}
			let preview = AVCaptureVideoPreviewLayer(session: session)
			preview.videoGravity = .resizeAspect
			return preview
		}

		/// Stop capturing input video
		public func stopDetection() {
			if let captureSession = self.captureSession {
				captureSession.stopRunning()
			}
			captureSession = nil
			self.detectionBlock = nil
			self.detector = nil
		}

		deinit {
			self.stopDetection()
		}

		// Private

		private var captureSession: AVCaptureSession?
		private var detector: CIDetector?
		private var detectionBlock: DetectionBlock?

		private let videoDataOutputQueue = {
			DispatchQueue(
				label: "QRCode.VideoDetector",
				qos: .userInitiated,
				attributes: [],
				autoreleaseFrequency: .inherit)
		}()
	}
}

@available(macOS 10.11, iOS 4, macCatalyst 14.0, *)
public extension QRCode.VideoDetector {
	func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
		if
			let block = self.detectionBlock,
			let imageBuf = CMSampleBufferGetImageBuffer(sampleBuffer),
			let image = Optional(CIImage(cvImageBuffer: imageBuf)),
			let features = detector?.features(in: image) as? [CIQRCodeFeature],
			features.count > 0
		{
			block(image, features)
		}
	}
}

#endif
