//
//  QRCodePixelShapePixel.swift
//
//  Copyright © 2024 Darren Ford. All rights reserved.
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

import CoreGraphics
import Foundation

internal extension QRCode.PixelShape {
	// A data shape generator where every pixel in the qr code becomes a discrete shape
	class CommonPixelGenerator {
		enum PixelType: String, CaseIterable {
			case square
			case circle
			case crt
			case roundedRect
			case squircle
			case sharp
			case star
			case flower
			case shiny
			case donut
			static var availableTypes: [String] = Self.allCases.map { $0.rawValue }
		}

		let pixelType: PixelType

		// Pixel inset routine
		var insetGenerator: QRCodePixelInsetGenerator

		var insetFraction: CGFloat = 0

		// The fractional corner radius for the pixel (0.0 -> 1.0)
		var cornerRadiusFraction: CGFloat

		// The rotation for each pixel (0.0 -> 1.0)
		var rotationFraction: CGFloat = 0
		// If true, randomly chooses a rotation for each pixel
		var useRandomRotation: Bool = false

		/// Create
		/// - Parameters:
		///   - pixelType: The type of pixel to use (eg. square, circle)
		///   - cornerRadiusFraction: For types that support it, the roundedness of the corners (0 -> 1)
		///   - insetGenerator: The inset function to apply across the matrix
		///   - insetFraction: The inset within the each pixel to generate the pixel's path (0 -> 1)
		///   - rotationFraction: A rotation factor (0 -> 1) to apply to the rotation of each pixel
		///   - useRandomRotation: If true, randomly sets the rotation of each pixel within the range `0 ... rotationFraction`
		init(
			pixelType: PixelType,
			cornerRadiusFraction: CGFloat = 0,
			insetGenerator: QRCodePixelInsetGenerator = QRCode.PixelInset.Fixed(),
			insetFraction: CGFloat = 0,
			rotationFraction: CGFloat = 0,
			useRandomRotation: Bool = false
		) {
			self.pixelType = pixelType
			self.insetGenerator = insetGenerator
			self.insetFraction = insetFraction

			self.cornerRadiusFraction = cornerRadiusFraction.clamped(to: 0 ... 1)
			
			self.rotationFraction = rotationFraction.clamped(to: 0 ... 1)
			self.useRandomRotation = useRandomRotation
		}

		func generatePath(from matrix: BoolMatrix, size: CGSize) -> CGPath {
			let dx = size.width / CGFloat(matrix.dimension)
			let dy = size.height / CGFloat(matrix.dimension)
			let dm = min(dx, dy)

			let xoff = (size.width - (CGFloat(matrix.dimension) * dm)) / 2.0
			let yoff = (size.height - (CGFloat(matrix.dimension) * dm)) / 2.0

			let path = CGMutablePath()

			let rotationBase: CGAffineTransform = {
				if rotationFraction == 0.0 {
					return CGAffineTransform.identity
				}
				else {
					return CGAffineTransform(rotationAngle: rotationFraction * CGFloat.pi)
				}
			}()

			// We want a consistent random number
			var rotationRandomGenerator = SplitMix64(seed: 183691261160545909)

			// Reset the inset generator
			self.insetGenerator.reset()

			for row in 0 ..< matrix.dimension {
				for col in 0 ..< matrix.dimension {
					// If the pixel is 'off' then we move on to the next
					guard matrix[row, col] == true else { continue }

					// Calculate the required pixel inset
					let insetFraction = self.insetGenerator.insetValue(
						for: matrix,
						row: row,
						column: col,
						insetFraction: self.insetFraction
					)

					let origX = xoff + (CGFloat(col) * dm) + (dm / 2)
					let origY = yoff + (CGFloat(row) * dm) + (dm / 2)

					let r = CGRect(x: xoff + (CGFloat(col) * dm), y: yoff + (CGFloat(row) * dm), width: dm, height: dm)
					let insetValue = insetFraction * (r.height / 2.0)
					let ri = r.insetBy(dx: insetValue, dy: insetValue)

					let rotatetfm: CGAffineTransform = {
						if self.useRandomRotation {
							return CGAffineTransform(
								rotationAngle: CGFloat.random(
									in: -self.rotationFraction...self.rotationFraction,
									using: &rotationRandomGenerator) * CGFloat.pi
							)
						}
						return rotationBase
					}()

					var rotateTransform = CGAffineTransform(translationX: -origX, y: -origY)
						.concatenating(rotatetfm)
						.concatenating(CGAffineTransform(translationX: origX, y: origY))

					if self.pixelType == .roundedRect {
						let cr = (ri.height / 2.0) * self.cornerRadiusFraction
						path.addPath(CGPath(roundedRect: ri, cornerWidth: cr, cornerHeight: cr, transform: &rotateTransform))
					}
					else if self.pixelType == .circle {
						path.addPath(CGPath(ellipseIn: ri, transform: nil))
					}
					else if self.pixelType == .squircle {
						let transform = CGAffineTransform(scaleX: ri.width / 10, y: ri.width / 10)
							.concatenating(CGAffineTransform(
								translationX: xoff + (CGFloat(col) * dm) + insetValue,
								y: yoff + (CGFloat(row) * dm) + insetValue
							))
							.concatenating(rotateTransform)

						let sq = Squircle.squircle10x10()
						path.addPath(sq, transform: transform)
					}
					else if self.pixelType == .crt {
						let transform = CGAffineTransform(scaleX: ri.width / 10, y: ri.width / 10)
							.concatenating(CGAffineTransform(
								translationX: xoff + (CGFloat(col) * dm) + insetValue,
								y: yoff + (CGFloat(row) * dm) + insetValue
							))
							.concatenating(rotateTransform)

						let sq = CRT.crtPixel10x10()
						path.addPath(sq, transform: transform)
					}
					else if self.pixelType == .sharp {
						let transform = CGAffineTransform(scaleX: ri.width / 10, y: ri.width / 10)
							.concatenating(CGAffineTransform(
								translationX: xoff + (CGFloat(col) * dm) + insetValue,
								y: yoff + (CGFloat(row) * dm) + insetValue
							))
							.concatenating(rotateTransform)

						let sq = Sharp.sharp10x10()
						path.addPath(sq, transform: transform)
					}
					else if self.pixelType == .star {
						let transform = CGAffineTransform(scaleX: ri.width / 10, y: ri.width / 10)
							.concatenating(CGAffineTransform(
								translationX: xoff + (CGFloat(col) * dm) + insetValue,
								y: yoff + (CGFloat(row) * dm) + insetValue
							))
							.concatenating(rotateTransform)
						let sq = Star.star10x10()
						path.addPath(sq, transform: transform)
					}
					else if self.pixelType == .flower {
						let transform = CGAffineTransform(scaleX: ri.width / 10, y: ri.width / 10)
							.concatenating(CGAffineTransform(
								translationX: xoff + (CGFloat(col) * dm) + insetValue,
								y: yoff + (CGFloat(row) * dm) + insetValue
							))
							.concatenating(rotateTransform)
						let sq = Flower.flower10x10()
						path.addPath(sq, transform: transform)
					}
					else if self.pixelType == .shiny {
						let transform = CGAffineTransform(scaleX: ri.width / 8, y: ri.width / 8)
							.concatenating(CGAffineTransform(
								translationX: xoff + (CGFloat(col) * dm),
								y: yoff + (CGFloat(row) * dm)
							))
							.concatenating(CGAffineTransform(
								translationX: -(ri.width / 8),
								y: -(ri.width / 8)
							))
						let sq = Shiny.pathShiny(row: row, col: col)
						path.addPath(sq, transform: transform)
					}
					else if self.pixelType == .donut {
						let transform = CGAffineTransform(scaleX: ri.width / 10, y: ri.width / 10)
							.concatenating(CGAffineTransform(
								translationX: xoff + (CGFloat(col) * dm),
								y: yoff + (CGFloat(row) * dm)
							))
							.concatenating(CGAffineTransform(
								translationX: -(ri.width / 10),
								y: -(ri.width / 10)
							))
						let sq = Donut.donutPixel10x10()
						path.addPath(sq, transform: transform)
					}
					else {
						path.addPath(CGPath(rect: ri, transform: &rotateTransform))
					}
				}
			}
			return path
		}
	}
}

extension QRCode.PixelShape.CommonPixelGenerator {

	// Inset

	func setInsetFractionValue(_ value: Any?) -> Bool {
		guard let v = value else {
			self.insetFraction = 0
			return true
		}
		guard let v = CGFloatValue(v) else { return false }
		self.insetFraction = v
		return true
	}

	func setInsetGenerator(_ generator: QRCodePixelInsetGenerator) -> Bool {
		self.insetGenerator = generator
		return true
	}

	func setInsetGenerator(named value: Any?) -> Bool {
		guard
			let v = value as? String,
			let generator = QRCode.PixelInset.generator(named: v)
		else {
			return false
		}
		self.insetGenerator = generator
		return true
	}

	// Rotation

	func setRotationFraction(_ value: Any?) -> Bool {
		guard let v = value, let v = CGFloatValue(v) else {
			self.rotationFraction = 0.0
			return true
		}
		self.rotationFraction = v
		return true
	}

	func setUsesRandomRotation(_ value: Any?) -> Bool {
		guard let v = value, let v = BoolValue(v) else {
			self.useRandomRotation = false
			return true
		}
		self.useRandomRotation = v
		return true
	}

	func setCornerRadiusFraction(_ value: Any?) -> Bool {
		guard let v = value else {
			self.cornerRadiusFraction = 0
			return true
		}
		guard let v = CGFloatValue(v)?.clamped(to: 0...1) else { return false }
		self.cornerRadiusFraction = v
		return true
	}
}
