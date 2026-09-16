# frozen_string_literal: true

require "socket"

body = File.binread(File.join(__dir__, "index.html"))
server = TCPServer.new("0.0.0.0", 3000)

loop do
  client = server.accept
  begin
    client.gets
    client.each_line { |line| break if line == "\r\n" }
    client.write("HTTP/1.1 200 OK\r\n")
    client.write("Content-Type: text/html; charset=utf-8\r\n")
    client.write("Content-Length: #{body.bytesize}\r\n")
    client.write("Connection: close\r\n\r\n")
    client.write(body)
  ensure
    client.close
  end
end
