import Foundation

func runLyricsTests() {
    let lrc = """
    [00:00.000] 作词 : Lucky 小爱
    [00:01.000] 作曲 : Lucky 小爱
    [00:30.542]故事的小黄花
    [00:34.100]时间：它从不等人
    [00:40.000]从出生那年就飘着
    """
    let lines = buildLyrics(lrc: lrc, translation: nil)
    expectEqual(lines.map(\.text), ["故事的小黄花", "时间：它从不等人", "从出生那年就飘着"], "credit lines are dropped, lyrics with colons stay")
    expectTrue(lines.allSatisfy { $0.translation == nil }, "no translation without tlyric")

    let jp = "[00:10.00]夢ならばどれほどよかったでしょう\n[00:16.20]未だにあなたのことを夢にみる\n[00:22.00]忘れた物を取りに帰るように"
    let zh = "[by:译者]\n[00:10.05]如果这一切都是梦境该有多好\n[00:22.00]就像回去取回遗忘的东西一样"
    let merged = buildLyrics(lrc: jp, translation: zh)
    expectEqual(merged.map(\.translation), ["如果这一切都是梦境该有多好", nil, "就像回去取回遗忘的东西一样"],
                "translations attach by timestamp within 0.3 s; missing ones stay nil")
    expectTrue(isCreditLine("Composer: Kenshi Yonezu") && !isCreditLine("我说：再见"), "credit detection")
    print("LyricsTests passed")
}
