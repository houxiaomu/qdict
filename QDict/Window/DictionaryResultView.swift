import SwiftUI

struct DictionaryResultView: View {
    let result: DictionaryResult

    private static let labelColor = Color.secondary.opacity(0.7)
    private static let accentColor = Color(red: 0.77, green: 0.47, blue: 0.23)

    // No ScrollView: dictionary output is bounded by the prompt
    // (1-3 defs, 2-3 examples, ≤4 synonyms, 1 usage line), so the panel
    // can grow with content. Scrollbars are reserved gutter even when
    // not needed and clash with the "concise dictionary" feel.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if result.senses.isEmpty {
                primaryRow
                flatDefinitionsBlock
            } else {
                sensesBlock
            }
            examplesBlock
            synonymsBlock
            usageBlock
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sections

    @ViewBuilder
    private var headerRow: some View {
        if result.word != nil || result.ipa != nil {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let word = result.word {
                    Text(word)
                        .font(.system(size: 24, weight: .semibold))
                        .tracking(-0.3)
                }
                if let ipa = result.ipa {
                    Text(ipa)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var primaryRow: some View {
        if let trans = result.primaryTranslation {
            HStack(alignment: .center, spacing: 8) {
                Text(trans)
                    .font(.system(size: 18, weight: .medium))
                if let pos = result.primaryPOS {
                    posPill(pos)
                }
            }
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var flatDefinitionsBlock: some View {
        if !result.flatDefinitions.isEmpty {
            sectionLabel("释义")
            VStack(alignment: .leading, spacing: 2) {
                ForEach(result.flatDefinitions, id: \.n) { def in
                    definitionRow(def)
                }
            }
        }
    }

    @ViewBuilder
    private var sensesBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(result.senses.indices, id: \.self) { i in
                let s = result.senses[i]
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.pos)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Self.accentColor)
                    if let primary = s.primary {
                        Text(primary)
                            .font(.system(size: 16, weight: .medium))
                    }
                    if !s.definitions.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(s.definitions, id: \.n) { def in
                                definitionRow(def)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var examplesBlock: some View {
        if !result.examples.isEmpty {
            sectionLabel("例句")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(result.examples.indices, id: \.self) { i in
                    let e = result.examples[i]
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.source).font(.system(size: 13))
                        Text(e.translation).font(.system(size: 12.5)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var synonymsBlock: some View {
        if !result.synonyms.isEmpty {
            sectionLabel("近义")
            HStack(spacing: 10) {
                ForEach(result.synonyms, id: \.self) { syn in
                    Text(syn).font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var usageBlock: some View {
        if let usage = result.usage {
            sectionLabel("用法")
            Text(usage).font(.system(size: 12.5)).foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func definitionRow(_ def: Definition) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(def.n)")
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .frame(minWidth: 14, alignment: .leading)
            Text(def.text)
                .font(.system(size: 13.5))
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Self.labelColor)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    private func posPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
    }
}

#Preview("apple") {
    DictionaryResultView(result: DictionaryResult(
        word: "apple",
        ipa: "/ˈæp.əl/",
        primaryTranslation: "苹果",
        primaryPOS: "名词",
        flatDefinitions: [
            Definition(n: 1, text: "一种常见、圆形的水果，外皮通常红色、绿色或黄色，果肉白色。"),
            Definition(n: 2, text: "专有名词。指 Apple Inc.，美国跨国科技公司。"),
        ],
        examples: [
            Example(source: "She ate a crisp red apple for a snack.", translation: "她吃了一个脆红苹果当点心。"),
            Example(source: "He works as a software engineer at Apple.", translation: "他在苹果公司担任软件工程师。"),
        ],
        synonyms: ["fruit", "orchard", "iPhone", "Mac"]
    ))
    .frame(width: 480)
}

#Preview("run (multi-POS)") {
    DictionaryResultView(result: DictionaryResult(
        word: "run",
        ipa: "/rʌn/",
        senses: [
            Sense(pos: "动词", primary: "跑；运行；经营", definitions: [
                Definition(n: 1, text: "用脚快速移动。"),
                Definition(n: 2, text: "使（机器、程序）工作。"),
                Definition(n: 3, text: "管理或经营。"),
            ]),
            Sense(pos: "名词", primary: "奔跑；一段时期", definitions: [
                Definition(n: 1, text: "快速移动的过程。"),
            ]),
        ],
        examples: [
            Example(source: "She runs every morning.", translation: "她每天早上跑步。"),
            Example(source: "He runs a small bakery.", translation: "他经营一家小面包店。"),
        ],
        usage: "\"run a business\" 是高频搭配。"
    ))
    .frame(width: 480)
}
