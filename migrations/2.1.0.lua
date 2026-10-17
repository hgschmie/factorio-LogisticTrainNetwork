--
-- cleanups after first major refactor
--

---@diagnostic disable-next-line: inject-field
-- modern factorio no longer needs the message buffer
storage.messageBuffer = nil
