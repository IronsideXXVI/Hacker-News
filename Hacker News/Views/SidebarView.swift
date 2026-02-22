import SwiftUI

struct SidebarView: View {
    @Bindable var viewModel: FeedViewModel
    @State private var listSelection: HNItem?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Content", selection: $viewModel.contentType) {
                    ForEach(HNContentType.allCases.filter { !$0.requiresAuth || viewModel.loggedInUsername != nil }) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .labelsHidden()
                Picker("Sort", selection: $viewModel.displaySort) {
                    ForEach(HNDisplaySort.allCases) { sort in
                        Text(sort.displayName).tag(sort)
                    }
                }
                .labelsHidden()
                Picker("Date", selection: $viewModel.dateRange) {
                    ForEach(HNDateRange.allCases) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Spacer().frame(height: 6)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task { await viewModel.searchStories() }
                    }
                if viewModel.isSearchActive {
                    Button {
                        viewModel.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Spacer().frame(height: 6)
            Divider()

            storyListView
        }
    }

    private var storyListView: some View {
        Group {
            if let error = viewModel.errorMessage, viewModel.stories.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Text("Failed to load stories")
                        .font(.system(size: 15 * viewModel.textScale, weight: .semibold))
                    Text(error)
                        .font(.system(size: 10 * viewModel.textScale))
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await viewModel.loadFeed() }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: $listSelection) {
                    ForEach(Array(viewModel.stories.enumerated()), id: \.element.id) { index, item in
                        RowSelectionReader { isSelected in
                            Group {
                                if item.type == "comment" {
                                    CommentRowView(comment: item, textScale: viewModel.textScale, isSelected: isSelected) { username in
                                        if let url = URL(string: "https://news.ycombinator.com/user?id=\(username)") {
                                            viewModel.navigateToProfile(url: url)
                                        }
                                    }
                                } else {
                                    StoryRowView(story: item, rank: index + 1, textScale: viewModel.textScale, isSelected: isSelected) { username in
                                        if let url = URL(string: "https://news.ycombinator.com/user?id=\(username)") {
                                            viewModel.navigateToProfile(url: url)
                                        }
                                    }
                                }
                            }
                        }
                        .tag(item)
                        .onAppear {
                            Task { await viewModel.loadMoreIfNeeded(currentItem: item) }
                        }
                    }

                    if viewModel.isLoading && !viewModel.stories.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        }
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: listSelection) { _, newValue in
                    if let story = newValue {
                        viewModel.navigate(to: story)
                    }
                }
                .onChange(of: viewModel.selectedStory) { _, newValue in
                    if listSelection != newValue {
                        listSelection = newValue
                    }
                }
            }
        }
    }

}

// MARK: - Row Selection Observer

private struct RowSelectionReader<Content: View>: View {
    @State private var isSelected = false
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(isSelected)
            .background(RowSelectionObserver(isSelected: $isSelected))
    }
}

private struct RowSelectionObserver: NSViewRepresentable {
    @Binding var isSelected: Bool

    func makeNSView(context: Context) -> RowSelectionNSView {
        let view = RowSelectionNSView()
        view.onSelectionChange = { selected in
            isSelected = selected
        }
        return view
    }

    func updateNSView(_ nsView: RowSelectionNSView, context: Context) {}
}

private class RowSelectionNSView: NSView {
    var onSelectionChange: ((Bool) -> Void)?
    private var selectedObservation: NSKeyValueObservation?
    private var emphasizedObservation: NSKeyValueObservation?
    private weak var rowView: NSTableRowView?

    override var intrinsicContentSize: NSSize { .zero }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        attemptObservation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attemptObservation()
    }

    private func attemptObservation() {
        guard selectedObservation == nil, superview != nil else { return }

        if !findAndObserveRowView() {
            DispatchQueue.main.async { [weak self] in
                self?.findAndObserveRowView()
            }
        }
    }

    private func notifyChange() {
        guard let rowView else { return }
        let highlighted = rowView.isSelected && rowView.isEmphasized
        DispatchQueue.main.async { [weak self] in
            self?.onSelectionChange?(highlighted)
        }
    }

    @discardableResult
    private func findAndObserveRowView() -> Bool {
        guard selectedObservation == nil else { return true }

        var current: NSView? = superview
        while let view = current {
            if let row = view as? NSTableRowView {
                rowView = row
                selectedObservation = row.observe(\.isSelected, options: [.new, .initial]) { [weak self] _, _ in
                    self?.notifyChange()
                }
                emphasizedObservation = row.observe(\.isEmphasized, options: [.new]) { [weak self] _, _ in
                    self?.notifyChange()
                }
                return true
            }
            current = view.superview
        }
        return false
    }
}
