import SwiftUI
import UIKit

/// A `UITextView` that grows with its text from one to `maxLines` lines and scrolls beyond that.
struct GrowingTextView: UIViewRepresentable {
    let text: String
    var maxLines = 6
    let onChange: (String) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.isScrollEnabled = false
        textView.delegate = context.coordinator
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.accessibilityLabel = "Message"
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onChange = onChange
        if textView.text != text {
            textView.text = text
            textView.invalidateIntrinsicContentSize()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView textView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let lineHeight = textView.font?.lineHeight ?? UIFont.preferredFont(forTextStyle: .body).lineHeight
        let insets = textView.textContainerInset.top + textView.textContainerInset.bottom
        let minHeight = ceil(lineHeight + insets)
        let maxHeight = ceil(lineHeight * CGFloat(maxLines) + insets)
        let fitting = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let scrolls = fitting > maxHeight
        if textView.isScrollEnabled != scrolls { textView.isScrollEnabled = scrolls }
        return CGSize(width: width, height: min(max(fitting, minHeight), maxHeight))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var onChange: (String) -> Void

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }

        func textViewDidChange(_ textView: UITextView) {
            onChange(textView.text)
        }
    }
}
