import Foundation

/// Fixed sample content for `--review-preview` and `--render-ui`, so the interface can be
/// inspected without a Codex account or a live selection.
enum UISamples {
    static let originalText = """
    hi team, pls review the attached q3 report and send feedback by friday. \
    also we need to decide on the vendor before the board meeting, i think option B is better \
    but lets discuss. thanks
    """

    static let draftText = """
    Hi team,

    Please review the attached Q3 report and send your feedback by Friday.

    We also need to decide on the vendor before the board meeting. I believe Option B is the \
    stronger choice, but let's discuss it together.

    Thanks
    """

    static let originalTextChinese = "各位 下周三的评审会我可能去不了 有几个数据还没跑完 麻烦谁帮我顶一下 我把材料先发群里"

    static let draftTextChinese = """
    各位好：

    下周三的评审会我可能无法出席，还有几项数据尚未完成核算。麻烦哪位同事帮忙代为主持，我会提前把材料发到群里。

    谢谢！
    """
}
