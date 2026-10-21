//===----------------------------------------------------------------------===//
// Copyright © 2026 Apple Inc. and the Containerization project authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

import Foundation
import SystemPackage
import Testing

@testable import ContainerizationEXT4

@Suite
struct EXT4ReaderSparseTests {
    /// A file whose middle block is all zeros: the formatter may store that
    /// block as a hole, and reading the file back must still return every byte.
    @Test func readFileReturnsZerosForHoles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ext4-sparse-\(UUID().uuidString).img")
        defer { try? FileManager.default.removeItem(at: url) }
        let block = 4096
        var contents = Data(repeating: 0x41, count: block)
        contents.append(Data(repeating: 0, count: block * 3))
        contents.append(Data(repeating: 0x42, count: block))
        contents.append(Data(repeating: 0x43, count: 100))

        let formatter = try EXT4.Formatter(FilePath(url.path), minDiskSize: 4 * 1024 * 1024)
        let stream = InputStream(data: contents)
        stream.open()
        try formatter.create(path: FilePath("/sparse"), mode: EXT4.Inode.Mode(.S_IFREG, 0o644), buf: stream)
        stream.close()
        try formatter.close()

        let reader = try EXT4.EXT4Reader(blockDevice: FilePath(url.path))
        let read = try reader.readFile(at: FilePath("/sparse"))
        #expect(read.count == contents.count)
        #expect(read == contents)

        // A read that starts after the hole.
        let tail = try reader.readFile(at: FilePath("/sparse"), offset: UInt64(block * 4), count: block)
        #expect(tail == Data(repeating: 0x42, count: block))
    }

    /// The same file in an image made by e2fsprogs (`mke2fs -d`), which stores
    /// zero blocks as holes. Skipped where mke2fs is not installed.
    @Test func readFileOfAnE2fsprogsSparseFile() throws {
        guard let mke2fs = ["/usr/sbin/mke2fs", "/sbin/mke2fs"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ext4-src-\(UUID().uuidString)")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ext4-e2fs-\(UUID().uuidString).img")
        defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: url) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let block = 4096
        var contents = Data(repeating: 0x41, count: block)
        contents.append(Data(repeating: 0, count: block * 3))
        contents.append(Data(repeating: 0x42, count: block))
        contents.append(Data(repeating: 0x43, count: 100))
        try contents.write(to: dir.appendingPathComponent("sparse"))
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 8 * 1024 * 1024)
        try handle.close()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: mke2fs)
        process.arguments = ["-q", "-F", "-t", "ext4", "-d", dir.path, url.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let reader = try EXT4.EXT4Reader(blockDevice: FilePath(url.path))
        let read = try reader.readFile(at: FilePath("/sparse"))
        #expect(read.count == contents.count)
        #expect(read == contents)
    }
}
