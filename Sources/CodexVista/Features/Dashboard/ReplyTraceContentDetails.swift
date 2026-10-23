import SwiftUI

struct ReplyTraceContentLoader: View {
    let node: ReplyTraceNode
    @State private var content: ReplyTraceNodeContent?
    @State private var error: String?
    @State private var reload = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(node.name).font(.system(size: 15, weight: .semibold))
                if let content {
                    ReplyTraceContentDetails(content: content)
                    Button("重新读取") { reload += 1 }.buttonStyle(.link)
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("重试") { reload += 1 }
                } else {
                    ProgressView("读取本地内容…").controlSize(.small)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: reload) {
            content = nil
            error = nil
            do {
                let loaded = try await ReplyTraceService.shared.loadContent(node: node)
                try Task.checkCancellation()
                content = loaded
            } catch is CancellationError {
                // Changing selection or closing the inspector discards pending content.
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }
}

struct ReplyTraceContentDetails: View {
    let content: ReplyTraceNodeContent

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("仅在本机按需读取，不写入统计数据库或日志。复制只包含当前已加载内容。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            if !content.found {
                notice("未找到可关联的节点记录。旧版记录可能缺少节点 ID，进行中的节点可重新读取。")
            }
            if content.incomplete { notice("部分记录无法读取、尚未写完或超过扫描上限，内容可能不完整。") }
            if content.truncated { notice("内容较长，已限制展示范围；每段最多 16,384 字符，每侧最多 32 段、65,536 字符。") }
            if content.crossedCompaction { notice("此前发生上下文压缩，输入仅包含压缩后可读取的片段。") }
            section("输入内容", scope: content.inputScope, blocks: content.input,
                    empty: "没有可关联的输入文本；原始记录未保存完整请求。")
            Divider()
            section("输出内容", scope: content.outputScope, blocks: content.output,
                    empty: "没有可显示的输出文本，可能尚未写入或未保存明文。")
        }
    }

    private func section(_ title: String, scope: String, blocks: [ReplyTraceTextBlock], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(blocks.map { "[\($0.title)]\n\($0.text)" }.joined(separator: "\n\n"), forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless).disabled(blocks.isEmpty)
                .help("复制\(title)").accessibilityLabel("复制\(title)")
            }
            Text(scope).font(.system(size: 10)).foregroundStyle(.secondary)
            if blocks.isEmpty {
                Text(empty).font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(blocks) { block in ReplyTraceTextBlockView(block: block) }
            }
        }
    }

    private func notice(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

private struct ReplyTraceTextBlockView: View {
    let block: ReplyTraceTextBlock
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(block.title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Text(verbatim: expanded ? block.text : String(block.text.prefix(280)))
                .font(.system(size: 11)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if block.text.count > 280 {
                Button(expanded ? "收起" : "展开已加载内容") { expanded.toggle() }
                    .buttonStyle(.link).font(.system(size: 10))
            }
            if block.truncated {
                Text("此段已截断").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
