/*
 MIT License

 Copyright (c) 2017-2018 MessageKit

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

import UIKit

/// A subclass of `UIViewController` with a `MessagesCollectionView` object
/// that is used to display conversation interfaces.
open class MessagesViewController: UIViewController,
UICollectionViewDelegateFlowLayout, UICollectionViewDataSource {

    /// The `MessagesCollectionView` managed by the messages view controller object.
    open var messagesCollectionView = MessagesCollectionView()

    /// The `MessageInputBar` used as the `inputAccessoryView` in the view controller.
    open var messageInputBar = MessageInputBar()

    /// A Boolean value that determines whether the `MessagesCollectionView` scrolls to the
    /// bottom whenever the `InputTextView` begins editing.
    ///
    /// The default value of this property is `false`.
    open var scrollsToBottomOnKeybordBeginsEditing: Bool = false
    
    /// A Boolean value that determines whether the `MessagesCollectionView`
    /// maintains it's current position when the height of the `MessageInputBar` changes.
    ///
    /// The default value of this property is `false`.
    open var maintainPositionOnKeyboardFrameChanged: Bool = false
    
    /// A Boolean value indicating if the `TypingBubbleCell` has been inserted at the last
    /// `IndexPath` of the `MessagesCollectionViewCell`
    public private(set) var isTypingIndicatorHidden: Bool = true
    
    /// A CGFloat value that determines the spacing between the message and
    /// the `TypingBubbleCell`
    ///
    /// The default value of this property is `10`
    open var typingIndicatorTopInset: CGFloat = 10
    
    /// A property that determines the color of the `TypingBubble` within the `TypingBubbleCell`
    ///
    /// The default value of this property is `UIColor.incomingGray`
    open var typingBubbleBackgroundColor: UIColor = .incomingGray
    
    /// A property that determines the color of the `TypingIndicator` dots within the `TypingBubble`
    ///
    /// The default value of this property is `UIColor.lightGray`
    open var typingBubbleDotColor: UIColor = .lightGray

    open override var canBecomeFirstResponder: Bool {
        return true
    }

    open override var inputAccessoryView: UIView? {
        return messageInputBar
    }

    open override var shouldAutorotate: Bool {
        return false
    }

    /// A CGFloat value that adds to (or, if negative, subtracts from) the automatically
    /// computed value of `messagesCollectionView.contentInset.bottom`. Meant to be used
    /// as a measure of last resort when the built-in algorithm does not produce the right
    /// value for your app. Please let us know when you end up having to use this property.
    open var additionalBottomInset: CGFloat = 0 {
        didSet {
            let delta = additionalBottomInset - oldValue
            messageCollectionViewBottomInset += delta
        }
    }

    private var isFirstLayout: Bool = true
    
    internal var isMessagesControllerBeingDismissed: Bool = false

    internal var selectedIndexPathForMenu: IndexPath?

    internal var messageCollectionViewBottomInset: CGFloat = 0 {
        didSet {
            messagesCollectionView.contentInset.bottom = messageCollectionViewBottomInset
            messagesCollectionView.scrollIndicatorInsets.bottom = messageCollectionViewBottomInset
        }
    }

    // MARK: - View Life Cycle

    open override func viewDidLoad() {
        super.viewDidLoad()
        setupDefaults()
        setupSubviews()
        setupConstraints()
        setupDelegates()
        addMenuControllerObservers()
        addObservers()
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isMessagesControllerBeingDismissed = false
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isMessagesControllerBeingDismissed = true
    }
    
    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isMessagesControllerBeingDismissed = false
    }
    
    open override func viewDidLayoutSubviews() {
        // Hack to prevent animation of the contentInset after viewDidAppear
        if isFirstLayout {
            defer { isFirstLayout = false }
            addKeyboardObservers()
            messageCollectionViewBottomInset = requiredInitialScrollViewBottomInset()
        }
        adjustScrollViewTopInset()
    }

    // MARK: - Initializers

    deinit {
        removeKeyboardObservers()
        removeMenuControllerObservers()
        removeObservers()
        clearMemoryCache()
    }

    // MARK: - Methods [Private]

    private func setupDefaults() {
        extendedLayoutIncludesOpaqueBars = true
        automaticallyAdjustsScrollViewInsets = false
        view.backgroundColor = .white
        messagesCollectionView.keyboardDismissMode = .interactive
        messagesCollectionView.alwaysBounceVertical = true
    }

    private func setupDelegates() {
        messagesCollectionView.delegate = self
        messagesCollectionView.dataSource = self
    }

    private func setupSubviews() {
        view.addSubview(messagesCollectionView)
    }

    private func setupConstraints() {
        messagesCollectionView.translatesAutoresizingMaskIntoConstraints = false
        
        let top = messagesCollectionView.topAnchor.constraint(equalTo: view.topAnchor, constant: topLayoutGuide.length)
        let bottom = messagesCollectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        if #available(iOS 11.0, *) {
            let leading = messagesCollectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
            let trailing = messagesCollectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
            NSLayoutConstraint.activate([top, bottom, trailing, leading])
        } else {
            let leading = messagesCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
            let trailing = messagesCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            NSLayoutConstraint.activate([top, bottom, trailing, leading])
        }
    }
    
    // MARK: - Typing Indicator API
    
    /// Sets the typing indicator sate by inserting/deleting the `TypingBubbleCell`
    ///
    /// - Parameters:
    ///   - isHidden: A Boolean value that is to be the new state of the typing indicator
    ///   - animated: A Boolean value determining if the insertion is to be animated
    ///   - updates: A block of code that will be executed during `performBatchUpdates`
    ///              when `animated` is `TRUE` or before the `completion` block executes
    ///              when `animated` is `FALSE`
    ///   - completion: A completion block to execute after the insertion/deletion
    open func setTypingIndicatorHidden(_ isHidden: Bool, animated: Bool, whilePerforming updates: (() -> Void)? = nil, completion: ((Bool) -> Void)? = nil) {
        
        guard isTypingIndicatorHidden != isHidden else { return }
        
        let section = messagesCollectionView.numberOfSections
        
        isTypingIndicatorHidden = isHidden
        guard let messagesFlowLayout = messagesCollectionView.collectionViewLayout as? MessagesCollectionViewFlowLayout else {
            return
        }
        
        // Required so the layout knows to preserve the last section for the typing indicator
        messagesFlowLayout.isTypingIndicatorHidden = isHidden
        
        if animated {
            messagesCollectionView.performBatchUpdates({ [weak self] in
                self?.performUpdatesForTypingBubbleVisability(at: section)
                updates?()
            }, completion: completion)
        } else {
            performUpdatesForTypingBubbleVisability(at: section)
            updates?()
            completion?(true)
        }
    }
    
    /// Performs a delete or insert on the `MessagesCollectionView` on the provided section
    ///
    /// - Parameter section: The index to modify
    private func performUpdatesForTypingBubbleVisability(at section: Int) {
        if isTypingIndicatorHidden {
            // Delete the typing indicator cell
            messagesCollectionView.deleteSections([section - 1])
        } else {
            // Insert the typing indicator cell
            messagesCollectionView.insertSections([section])
        }
    }
    
    /// Determines if the section is reserved for the typing indicator bubble
    ///
    /// - Parameter section: The section to compare against
    /// - Returns: A Boolean value indicating if the section is reserved for the `TypingBubbleCell`
    public func isSectionReservedForTypingIndicator(_ section: Int) -> Bool {
        return !isTypingIndicatorHidden && section == self.numberOfSections(in: messagesCollectionView) - 1
    }
    
    /// Returns a dequeued `UICollectionViewCell` that is inserted when the typing indicator is shown
    ///
    /// - Parameter indexPath: The `IndexPath` the cell will appear at
    /// - Returns: A `UICollectionViewCell` designed to indicate another user is typing
    open func dequeuedTypingCell(for indexPath: IndexPath) -> UICollectionViewCell {
        let cell = messagesCollectionView.dequeueReusableCell(TypingBubbleCell.self, for: indexPath)
        cell.typingBubble.backgroundColor = typingBubbleBackgroundColor
        cell.typingBubble.typingIndicator.dotColor = typingBubbleDotColor
        cell.typingBubble.startAnimating()
        return cell
    }

    // MARK: - UICollectionViewDataSource

    open func numberOfSections(in collectionView: UICollectionView) -> Int {
        guard let collectionView = collectionView as? MessagesCollectionView else {
            fatalError(MessageKitError.notMessagesCollectionView)
        }
        let count = collectionView.messagesDataSource?.numberOfSections(in: collectionView) ?? 0
        return count + (isTypingIndicatorHidden ? 0 : 1)
    }

    open func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let collectionView = collectionView as? MessagesCollectionView else {
            fatalError(MessageKitError.notMessagesCollectionView)
        }
        if isSectionReservedForTypingIndicator(section) {
            return 1
        }
        return collectionView.messagesDataSource?.numberOfItems(inSection: section, in: collectionView) ?? 0
    }

    open func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        guard let messagesCollectionView = collectionView as? MessagesCollectionView else {
            fatalError(MessageKitError.notMessagesCollectionView)
        }
        
        guard !isSectionReservedForTypingIndicator(indexPath.section) else {
            return dequeuedTypingCell(for: indexPath)
        }

        guard let messagesDataSource = messagesCollectionView.messagesDataSource else {
            fatalError(MessageKitError.nilMessagesDataSource)
        }

        let message = messagesDataSource.messageForItem(at: indexPath, in: messagesCollectionView)

        switch message.kind {
        case .text, .attributedText, .emoji:
            let cell = messagesCollectionView.dequeueReusableCell(TextMessageCell.self, for: indexPath)
            cell.configure(with: message, at: indexPath, and: messagesCollectionView)
            return cell
        case .photo, .video:
            let cell = messagesCollectionView.dequeueReusableCell(MediaMessageCell.self, for: indexPath)
            cell.configure(with: message, at: indexPath, and: messagesCollectionView)
            return cell
        case .location:
            let cell = messagesCollectionView.dequeueReusableCell(LocationMessageCell.self, for: indexPath)
            cell.configure(with: message, at: indexPath, and: messagesCollectionView)
            return cell
        case .custom:
            fatalError(MessageKitError.customDataUnresolvedCell)
        }
    }

    open func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {

        guard let messagesCollectionView = collectionView as? MessagesCollectionView else {
            fatalError(MessageKitError.notMessagesCollectionView)
        }

        guard let displayDelegate = messagesCollectionView.messagesDisplayDelegate else {
            fatalError(MessageKitError.nilMessagesDisplayDelegate)
        }

        switch kind {
        case UICollectionElementKindSectionHeader:
            return displayDelegate.messageHeaderView(for: indexPath, in: messagesCollectionView)
        case UICollectionElementKindSectionFooter:
            return displayDelegate.messageFooterView(for: indexPath, in: messagesCollectionView)
        default:
            fatalError(MessageKitError.unrecognizedSectionKind)
        }
    }

    // MARK: - UICollectionViewDelegateFlowLayout

    open func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let messagesFlowLayout = collectionViewLayout as? MessagesCollectionViewFlowLayout else { return .zero }
        return messagesFlowLayout.sizeForItem(at: indexPath)
    }

    open func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {

        guard let messagesCollectionView = collectionView as? MessagesCollectionView else {
            fatalError(MessageKitError.notMessagesCollectionView)
        }
        guard let layoutDelegate = messagesCollectionView.messagesLayoutDelegate else {
            fatalError(MessageKitError.nilMessagesLayoutDelegate)
        }
        guard !isSectionReservedForTypingIndicator(section) else {
            return CGSize(width: collectionView.bounds.width, height: typingIndicatorTopInset)
        }
        return layoutDelegate.headerViewSize(for: section, in: messagesCollectionView)
    }

    open func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize {
        guard let messagesCollectionView = collectionView as? MessagesCollectionView else {
            fatalError(MessageKitError.notMessagesCollectionView)
        }
        guard let layoutDelegate = messagesCollectionView.messagesLayoutDelegate else {
            fatalError(MessageKitError.nilMessagesLayoutDelegate)
        }
        guard !isSectionReservedForTypingIndicator(section) else {
            return .zero
        }
        return layoutDelegate.footerViewSize(for: section, in: messagesCollectionView)
    }

    open func collectionView(_ collectionView: UICollectionView, shouldShowMenuForItemAt indexPath: IndexPath) -> Bool {
        guard !isSectionReservedForTypingIndicator(indexPath.section) else {
            return false
        }
        guard let messagesDataSource = messagesCollectionView.messagesDataSource else { return false }
        let message = messagesDataSource.messageForItem(at: indexPath, in: messagesCollectionView)

        switch message.kind {
        case .text, .attributedText, .emoji, .photo:
            selectedIndexPathForMenu = indexPath
            return true
        default:
            return false
        }
    }

    open func collectionView(_ collectionView: UICollectionView, canPerformAction action: Selector, forItemAt indexPath: IndexPath, withSender sender: Any?) -> Bool {
        guard !isSectionReservedForTypingIndicator(indexPath.section) else {
            return false
        }
        return (action == NSSelectorFromString("copy:"))
    }

    open func collectionView(_ collectionView: UICollectionView, performAction action: Selector, forItemAt indexPath: IndexPath, withSender sender: Any?) {
        guard let messagesDataSource = messagesCollectionView.messagesDataSource else {
            fatalError(MessageKitError.nilMessagesDataSource)
        }
        let pasteBoard = UIPasteboard.general
        let message = messagesDataSource.messageForItem(at: indexPath, in: messagesCollectionView)

        switch message.kind {
        case .text(let text), .emoji(let text):
            pasteBoard.string = text
        case .attributedText(let attributedText):
            pasteBoard.string = attributedText.string
        case .photo(let mediaItem):
            pasteBoard.image = mediaItem.image ?? mediaItem.placeholderImage
        default:
            break
        }
    }

    // MARK: - Helpers
    
    private func addObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(clearMemoryCache), name: .UIApplicationDidReceiveMemoryWarning, object: nil)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self, name: .UIApplicationDidReceiveMemoryWarning, object: nil)
    }
    
    @objc private func clearMemoryCache() {
        MessageStyle.bubbleImageCache.removeAllObjects()
    }
}
