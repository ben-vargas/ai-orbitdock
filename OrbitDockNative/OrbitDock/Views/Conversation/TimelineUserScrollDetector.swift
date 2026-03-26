//
//  TimelineUserScrollDetector.swift
//  OrbitDock
//
//  Detects user-initiated scroll gestures on the enclosing platform scroll view.
//
//  macOS: NSScrollView.willStartLiveScrollNotification / didEndLiveScrollNotification
//         fire exclusively for user-initiated scroll (trackpad, mouse wheel) — never
//         for programmatic scrollTo calls or content size changes.
//
//  iOS:   Tracks the UIScrollView pan gesture recognizer state and deceleration
//         to cover the full drag + momentum lifecycle.
//

import SwiftUI

#if os(macOS)
  import AppKit

  struct TimelineUserScrollDetector: NSViewRepresentable {
    @Binding var isUserScrolling: Bool
    @Binding var isNearBottom: Bool
    let bottomThreshold: CGFloat

    func makeNSView(context: Context) -> ScrollDetectorNSView {
      ScrollDetectorNSView(
        isUserScrolling: $isUserScrolling,
        isNearBottom: $isNearBottom,
        bottomThreshold: bottomThreshold
      )
    }

    func updateNSView(_ nsView: ScrollDetectorNSView, context: Context) {
      nsView.bottomThreshold = bottomThreshold
      nsView.refreshMetrics()
    }
  }

  final class ScrollDetectorNSView: NSView {
    private let isUserScrolling: Binding<Bool>
    private let isNearBottom: Binding<Bool>
    private weak var observedScrollView: NSScrollView?
    var bottomThreshold: CGFloat

    // Track last-written values to coalesce redundant async dispatches.
    // Binding writes are deferred to the next run loop iteration so they
    // never fire during SwiftUI's layout pass (which triggers the
    // "Modifying state during view update" warnings).
    private var lastWrittenNearBottom: Bool = true
    private var lastWrittenUserScrolling: Bool = false

    init(
      isUserScrolling: Binding<Bool>,
      isNearBottom: Binding<Bool>,
      bottomThreshold: CGFloat
    ) {
      self.isUserScrolling = isUserScrolling
      self.isNearBottom = isNearBottom
      self.bottomThreshold = bottomThreshold
      super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError()
    }

    override func viewDidMoveToSuperview() {
      super.viewDidMoveToSuperview()
      rebindIfNeeded()
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      rebindIfNeeded()
    }

    override func layout() {
      super.layout()
      rebindIfNeeded()
    }

    private func rebindIfNeeded() {
      guard window != nil else {
        teardownObservers()
        return
      }

      guard let scrollView = findScrollView() else {
        if observedScrollView != nil {
          ConversationFollowDebug.log("TimelineUserScrollDetector.macOS detached scrollView")
        }
        teardownObservers()
        return
      }

      guard observedScrollView !== scrollView else {
        refreshMetrics()
        return
      }

      teardownObservers()
      observedScrollView = scrollView

      scrollView.contentView.postsBoundsChangedNotifications = true
      scrollView.documentView?.postsFrameChangedNotifications = true

      NotificationCenter.default.addObserver(
        self,
        selector: #selector(liveScrollStarted),
        name: NSScrollView.willStartLiveScrollNotification,
        object: scrollView
      )
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(liveScrollEnded),
        name: NSScrollView.didEndLiveScrollNotification,
        object: scrollView
      )
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(scrollMetricsChanged),
        name: NSView.boundsDidChangeNotification,
        object: scrollView.contentView
      )
      if let documentView = scrollView.documentView {
        NotificationCenter.default.addObserver(
          self,
          selector: #selector(scrollMetricsChanged),
          name: NSView.frameDidChangeNotification,
          object: documentView
        )
      }

      ConversationFollowDebug.log(
        "TimelineUserScrollDetector.macOS attached scrollView documentHeight=\(scrollView.documentView?.bounds.height ?? 0)"
      )
      refreshMetrics()
    }

    @objc private func liveScrollStarted() {
      ConversationFollowDebug.log("TimelineUserScrollDetector.macOS liveScrollStarted")
      deferUserScrolling(true)
      refreshMetrics()
    }

    @objc private func liveScrollEnded() {
      ConversationFollowDebug.log("TimelineUserScrollDetector.macOS liveScrollEnded")
      deferUserScrolling(false)
      refreshMetrics()
    }

    @objc private func scrollMetricsChanged() {
      refreshMetrics()
    }

    func refreshMetrics() {
      guard let scrollView = observedScrollView, let documentView = scrollView.documentView else {
        deferNearBottom(true)
        return
      }

      let visibleMaxY = scrollView.contentView.documentVisibleRect.maxY
      let contentMaxY = documentView.bounds.maxY
      let distanceFromBottom = max(contentMaxY - visibleMaxY, 0)
      deferNearBottom(distanceFromBottom <= bottomThreshold)
    }

    private func deferNearBottom(_ value: Bool) {
      guard lastWrittenNearBottom != value else { return }
      lastWrittenNearBottom = value
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.isNearBottom.wrappedValue = value
      }
    }

    private func deferUserScrolling(_ value: Bool) {
      guard lastWrittenUserScrolling != value else { return }
      lastWrittenUserScrolling = value
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.isUserScrolling.wrappedValue = value
      }
    }

    private func findScrollView() -> NSScrollView? {
      var view: NSView? = self
      while let candidate = view {
        if let scrollView = candidate as? NSScrollView { return scrollView }
        view = candidate.superview
      }
      return nil
    }

    private func teardownObservers() {
      NotificationCenter.default.removeObserver(self)
      observedScrollView = nil
    }

    deinit {
      teardownObservers()
    }
  }

#else
  import UIKit

  struct TimelineUserScrollDetector: UIViewRepresentable {
    @Binding var isUserScrolling: Bool
    @Binding var isNearBottom: Bool
    let bottomThreshold: CGFloat

    func makeUIView(context: Context) -> ScrollDetectorUIView {
      ScrollDetectorUIView(
        isUserScrolling: $isUserScrolling,
        isNearBottom: $isNearBottom,
        bottomThreshold: bottomThreshold
      )
    }

    func updateUIView(_ uiView: ScrollDetectorUIView, context: Context) {
      uiView.bottomThreshold = bottomThreshold
      uiView.refreshMetrics()
    }
  }

  final class ScrollDetectorUIView: UIView {
    var isUserScrolling: Binding<Bool>
    var isNearBottom: Binding<Bool>
    var bottomThreshold: CGFloat
    private var panObservation: NSKeyValueObservation?
    private var decelerationObservation: NSKeyValueObservation?
    private var contentOffsetObservation: NSKeyValueObservation?
    private var contentSizeObservation: NSKeyValueObservation?
    private var boundsObservation: NSKeyValueObservation?

    // Track last-written values to coalesce redundant async dispatches.
    private var lastWrittenNearBottom: Bool = true
    private var lastWrittenUserScrolling: Bool = false

    init(
      isUserScrolling: Binding<Bool>,
      isNearBottom: Binding<Bool>,
      bottomThreshold: CGFloat
    ) {
      self.isUserScrolling = isUserScrolling
      self.isNearBottom = isNearBottom
      self.bottomThreshold = bottomThreshold
      super.init(frame: .zero)
      isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError()
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      panObservation = nil
      decelerationObservation = nil
      contentOffsetObservation = nil
      contentSizeObservation = nil
      boundsObservation = nil
      guard window != nil else { return }
      guard let scrollView = findScrollView() else { return }

      panObservation = scrollView.panGestureRecognizer.observe(\.state) { [weak self] rec, _ in
        MainActor.assumeIsolated {
          self?.handlePanState(rec)
        }
      }
      contentOffsetObservation = scrollView.observe(\.contentOffset) { [weak self] _, _ in
        MainActor.assumeIsolated {
          self?.refreshMetrics()
        }
      }
      contentSizeObservation = scrollView.observe(\.contentSize) { [weak self] _, _ in
        MainActor.assumeIsolated {
          self?.refreshMetrics()
        }
      }
      boundsObservation = scrollView.observe(\.bounds) { [weak self] _, _ in
        MainActor.assumeIsolated {
          self?.refreshMetrics()
        }
      }
      refreshMetrics()
    }

    private func handlePanState(_ recognizer: UIPanGestureRecognizer) {
      switch recognizer.state {
        case .began, .changed:
          decelerationObservation = nil
          deferUserScrolling(true)
          refreshMetrics()

        case .ended:
          guard let scrollView = recognizer.view as? UIScrollView else {
            deferUserScrolling(false)
            refreshMetrics()
            return
          }
          // Track deceleration (momentum) — keep isUserScrolling true until it settles
          decelerationObservation = scrollView.observe(\.contentOffset) { [weak self] sv, _ in
            MainActor.assumeIsolated {
              self?.refreshMetrics()
              guard !sv.isDecelerating else { return }
              self?.decelerationObservation = nil
              self?.deferUserScrolling(false)
            }
          }

        case .cancelled, .failed:
          decelerationObservation = nil
          deferUserScrolling(false)
          refreshMetrics()

        default:
          break
      }
    }

    func refreshMetrics() {
      guard let scrollView = findScrollView() else {
        deferNearBottom(true)
        return
      }

      let insetBottom = scrollView.adjustedContentInset.bottom
      let visibleMaxY = scrollView.contentOffset.y + scrollView.bounds.height - insetBottom
      let contentMaxY = scrollView.contentSize.height
      let distanceFromBottom = max(contentMaxY - visibleMaxY, 0)
      deferNearBottom(distanceFromBottom <= bottomThreshold)
    }

    private func deferNearBottom(_ value: Bool) {
      guard lastWrittenNearBottom != value else { return }
      lastWrittenNearBottom = value
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.isNearBottom.wrappedValue = value
      }
    }

    private func deferUserScrolling(_ value: Bool) {
      guard lastWrittenUserScrolling != value else { return }
      lastWrittenUserScrolling = value
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.isUserScrolling.wrappedValue = value
      }
    }

    private func findScrollView() -> UIScrollView? {
      var view: UIView? = superview
      while let v = view {
        if let sv = v as? UIScrollView { return sv }
        view = v.superview
      }
      return nil
    }
  }
#endif
