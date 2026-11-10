import Foundation
import CoreImage

enum WatermarkEngine {
    static func remove(url: URL) throws -> Data {
        guard let resources = Bundle.main.resourceURL else { throw ImageFailure.message("找不到应用资源。") }
        let runtime = resources.appendingPathComponent("WatermarkRuntime")
        let python = runtime.appendingPathComponent("python/bin/python3.12")
        guard FileManager.default.isExecutableFile(atPath: python.path) else { throw ImageFailure.message("未找到内置水印处理组件，请重新安装应用。") }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("Luma-Watermark-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { throw ImageFailure.message("无法读取图片。") }
        let input = temp.appendingPathComponent("input.png")
        try ImageEngine.transparentPNG(image).write(to: input)
        let output = temp.appendingPathComponent("output")
        let stdoutURL = temp.appendingPathComponent("stdout")
        let stderrURL = temp.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdout = try FileHandle(forWritingTo: stdoutURL), stderr = try FileHandle(forWritingTo: stderrURL)
        defer { try? stdout.close(); try? stderr.close() }
        let process = Process()
        process.executableURL = python
        process.arguments = ["-m", "opennomark.cli", input.path, "-o", output.path, "--json"]
        var env = ProcessInfo.processInfo.environment
        env["PYTHONHOME"] = runtime.appendingPathComponent("python").path
        env["PYTHONPATH"] = runtime.appendingPathComponent("app").path
        env["HF_HOME"] = runtime.appendingPathComponent("models/huggingface").path
        env["HF_HUB_OFFLINE"] = "1"
        env["TRANSFORMERS_OFFLINE"] = "1"
        env["LUMA_LAMA_MODEL"] = runtime.appendingPathComponent("models/big-lama.pt").path
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = env
        process.standardOutput = stdout; process.standardError = stderr
        try process.run(); process.waitUntilExit()
        let raw = try Data(contentsOf: stdoutURL)
        guard let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let results = json["results"] as? [[String: Any]], let result = results.first else {
            let message = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
            throw ImageFailure.message("水印处理组件启动失败：\(message.suffix(400))")
        }
        guard result["status"] as? String == "cleaned", let path = result["output"] as? String else {
            throw ImageFailure.message("未检测到可去除的水印，请尝试其他图片。")
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }
}
