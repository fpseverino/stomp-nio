extension String {
    func trimmingWhitespace() -> Substring {
        self.trimmingWhitespacePrefix().trimmingWhitespaceSuffix()
    }

    func endOfWhitespacePrefix() -> String.Index {
        var index = self.startIndex
        while index < self.endIndex, self[index].isWhitespace {
            formIndex(after: &index)
        }
        return index
    }

    func trimmingWhitespacePrefix() -> Substring {
        let start = self.endOfWhitespacePrefix()
        return self[start..<self.endIndex]
    }
}

extension Substring {
    func startOfWhitespaceSuffix() -> Substring.Index {
        var index = self.endIndex
        while index > self.startIndex {
            let after = index
            formIndex(before: &index)
            if !self[index].isWhitespace {
                return after
            }
        }
        return index
    }

    func trimmingWhitespaceSuffix() -> Substring {
        let end = self.startOfWhitespaceSuffix()
        return self[self.startIndex..<end]
    }
}
