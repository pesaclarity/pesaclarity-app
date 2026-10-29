// Stand-in for Apple's AppIntents on Linux, for tool/swift_typecheck only. Declares just
// what ios/Runner uses, with Apple's signatures. Never shipped.
import Foundation
public struct LocalizedStringResource: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {}
}
public struct IntentDescription {
  public init(_ description: LocalizedStringResource) {}
}
public protocol IntentResult {}
public struct EmptyResult: IntentResult {}
extension IntentResult where Self == EmptyResult {
  public static func result() -> EmptyResult { EmptyResult() }
}
public protocol ParameterSummary {}
public struct SummaryString<Intent>: ExpressibleByStringInterpolation {
  public struct StringInterpolation: StringInterpolationProtocol {
    public init(literalCapacity: Int, interpolationCount: Int) {}
    public mutating func appendLiteral(_ literal: String) {}
    public mutating func appendInterpolation<Value>(_ keyPath: KeyPath<Intent, IntentParameter<Value>>) {}
  }
  public init(stringLiteral value: String) {}
  public init(stringInterpolation: StringInterpolation) {}
}
public struct Summary<Intent>: ParameterSummary {
  public init(_ text: SummaryString<Intent>) {}
}
@resultBuilder
public enum ParameterSummaryBuilder<Intent> {
  public static func buildExpression(_ summary: Summary<Intent>) -> Summary<Intent> { summary }
  public static func buildBlock(_ summary: Summary<Intent>) -> Summary<Intent> { summary }
}
public protocol AppIntent {
  static var title: LocalizedStringResource { get }
  associatedtype PerformResult: IntentResult
  associatedtype SummaryContent: ParameterSummary
  @ParameterSummaryBuilder<Self> static var parameterSummary: SummaryContent { get }
  func perform() async throws -> PerformResult
  init()
}
@propertyWrapper
public final class IntentParameter<Value> {
  private var value: Value?
  public init(title: LocalizedStringResource) {}
  public var wrappedValue: Value {
    get { value! }
    set { value = newValue }
  }
  public var projectedValue: IntentParameter<Value> { self }
}
public typealias Parameter = IntentParameter
