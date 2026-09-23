// SmartPreviewDetectorTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing
@testable import QuickUI

@Suite("智能预览识别")
struct SmartPreviewDetectorTests {

    @Test("网址")
    func detectsURL() {
        let previews = SmartPreviewDetector.detect("https://example.com/a")
        #expect(previews.contains { if case .url = $0 { return true } else { return false } })
    }

    @Test("色值")
    func detectsColor() {
        let previews = SmartPreviewDetector.detect("#FF5500")
        #expect(
            previews.contains {
                if case .color(let hex, _) = $0 { return hex == "#FF5500" } else { return false }
            })
    }

    @Test("IP 优先于网址")
    func detectsIP() {
        let previews = SmartPreviewDetector.detect("192.168.1.1")
        #expect(previews.contains { if case .ip = $0 { return true } else { return false } })
        #expect(!previews.contains { if case .url = $0 { return true } else { return false } })
    }

    @Test("邮箱")
    func detectsEmail() {
        let previews = SmartPreviewDetector.detect("hi@example.com")
        #expect(previews.contains { if case .email = $0 { return true } else { return false } })
    }

    @Test("算式求值")
    func detectsMath() {
        let previews = SmartPreviewDetector.detect("1+2*3")
        #expect(
            previews.contains {
                if case .math(_, let result) = $0 { return result == "7" } else { return false }
            })
    }

    @Test("SQL：SELECT ... WHERE")
    func detectsSelectWhere() {
        let previews = SmartPreviewDetector.detect(
            "select id, name from users where active = 1")
        #expect(
            previews.contains {
                if case .sql(let statement, _) = $0 { return statement == "SELECT" } else { return false }
            })
    }

    @Test("SQL：SELECT * FROM")
    func detectsSelectStar() {
        let previews = SmartPreviewDetector.detect("SELECT * FROM orders")
        #expect(previews.contains { if case .sql = $0 { return true } else { return false } })
    }

    @Test("SQL：DML / DDL 关键字")
    func detectsDML() {
        for text in [
            "INSERT INTO users (id, name) VALUES (1, 'a')",
            "UPDATE users SET name = 'b' WHERE id = 1",
            "DELETE FROM users WHERE id = 1",
            "CREATE TABLE t (id INT PRIMARY KEY)"
        ] {
            #expect(
                SmartPreviewDetector.detect(text).contains {
                    if case .sql = $0 { return true } else { return false }
                },
                "应识别为 SQL：\(text)")
        }
    }

    @Test("以 Select 开头的英文句子不误判为 SQL")
    func doesNotMisdetectEnglish() {
        let previews = SmartPreviewDetector.detect("Select the best option from the menu")
        #expect(!previews.contains { if case .sql = $0 { return true } else { return false } })
    }

    @Test("文件路径存在性由注入闭包决定")
    func detectsFilePathWithInjectedFS() {
        let previews = SmartPreviewDetector.detect(
            "/tmp/demo.txt",
            fileExists: { _ in true },
            isDirectory: { _ in false }
        )
        #expect(
            previews.contains {
                if case .filePath(let path, let exists, let isDir) = $0 {
                    return path == "/tmp/demo.txt" && exists && !isDir
                }
                return false
            })
    }

    @Test("无特征文本回落到纯文本")
    func fallsBackToPlainText() {
        let previews = SmartPreviewDetector.detect("!!! ???")
        #expect(previews.contains { if case .plainText = $0 { return true } else { return false } })
    }

    @Test("空输入返回空数组")
    func emptyInput() {
        #expect(SmartPreviewDetector.detect("   ").isEmpty)
    }
}
