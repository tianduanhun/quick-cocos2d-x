--[[
For quick-cocos2d-x
SocketTCP lua
@author zrong (zengrong.net)
Creation: 2013-11-12
Last Modification: 2013-12-05
@see http://cn.quick-x.com/?topic=quickkydsocketfzl
]]

local SOCKET_TICK_TIME = 0.03 			-- check socket data interval
local SOCKET_RECONNECT_TIME = 5			-- socket reconnect try interval
local SOCKET_CONNECT_FAIL_TIMEOUT = 3	-- socket failure timeout

local STATUS_CLOSED = "closed"
local STATUS_NOT_CONNECTED = "Socket is not connected"
local STATUS_ALREADY_CONNECTED = "already connected"
local STATUS_ALREADY_IN_PROGRESS = "Operation already in progress"
local STATUS_TIMEOUT = "timeout"

local scheduler = require("framework.scheduler")
local socket = require "socket"

local SocketTCP = class("SocketTCP")

SocketTCP.EVENT_DATA = "SOCKET_TCP_DATA"
SocketTCP.EVENT_CLOSE = "SOCKET_TCP_CLOSE"
SocketTCP.EVENT_CLOSED = "SOCKET_TCP_CLOSED"
SocketTCP.EVENT_CONNECTED = "SOCKET_TCP_CONNECTED"
SocketTCP.EVENT_CONNECT_FAILURE = "SOCKET_TCP_CONNECT_FAILURE"

SocketTCP._VERSION = socket._VERSION
SocketTCP._DEBUG = socket._DEBUG

function SocketTCP.getTime()
    return socket.gettime()
end

function SocketTCP:ctor(__host, __port, __retryConnectWhenFailure)
    require("framework.api.EventProtocol").extend(self)
    self.host = __host
    self.port = __port
    self.tickScheduler = nil			-- timer for data
    self.reconnectScheduler = nil		-- timer for reconnect
    self.connectTimeTickScheduler = nil	-- timer for connect timeout
    self.name = 'SocketTCP'
    self.tcp = nil
    self.isRetryConnect = __retryConnectWhenFailure
    self.isConnected = false
    self.packet = 4
    self.buf = ""
    self.msgLen = 0
end

function SocketTCP:setName( __name )
    self.name = __name
    return self
end

function SocketTCP:setTickTime(__time)
    SOCKET_TICK_TIME = __time
    return self
end

function SocketTCP:setReconnTime(__time)
    SOCKET_RECONNECT_TIME = __time
    return self
end

function SocketTCP:setConnFailTime(__time)
    SOCKET_CONNECT_FAIL_TIMEOUT = __time
    return self
end

function SocketTCP:connect(__host, __port, __retryConnectWhenFailure)
    if __host then self.host = __host end
    if __port then self.port = __port end
    if __retryConnectWhenFailure ~= nil then self.isRetryConnect = __retryConnectWhenFailure end
    assert(self.host or self.port, "Host and port are necessary!")
    --echoInfo("%s.connect(%s, %d)", self.name, self.host, self.port)
    self.tcp = socket.tcp()
    self.tcp:settimeout(0)

    local function __checkConnect()
        local __succ = self:_connect() 
        if __succ then
            self:_onConnected()
        end
        return __succ
    end

    if not __checkConnect() then
        -- check whether connection is success
        -- the connection is failure if socket isn't connected after SOCKET_CONNECT_FAIL_TIMEOUT seconds
        local __connectTimeTick = function ()
            --echoInfo("%s.connectTimeTick", self.name)
            if self.isConnected then return end
            self.waitConnect = self.waitConnect or 0
            self.waitConnect = self.waitConnect + SOCKET_TICK_TIME
            echoInfo("waitConnect:%0.2f, SOCKET_TICK_TIME:%0.2f,SOCKET_CONNECT_FAIL_TIMEOUT:%0.2f", self.waitConnect,SOCKET_TICK_TIME, SOCKET_CONNECT_FAIL_TIMEOUT)
            if self.waitConnect >= SOCKET_CONNECT_FAIL_TIMEOUT then
                self.waitConnect = nil
                self:close()
                self:_connectFailure()
            end
            __checkConnect()
        end
        self.connectTimeTickScheduler = scheduler.scheduleGlobal(__connectTimeTick, SOCKET_TICK_TIME)
    end
end

function SocketTCP:send(__data)
    assert(self.isConnected, self.name .. " is not connected.")
    local _len = __data:getLen()
    local _head = cc.utils.ByteArray.new(cc.utils.ByteArray.ENDIAN_BIG)
    _head:writeInt(_len)
    self.tcp:send(_head:getPack())
    local __dataPack = __data:getPack()
    local res, reason, k, j
    if _len < 1024 then
        res, reason, k, j = self.tcp:send(__dataPack)
    else
        local i = 0
        local res, reason = nil
        while (i + 1024 < _len) do
            res, reason, k, j = self.tcp:send(__dataPack, i + 1, i + 1024)
            i = i + 1024
        end
        res, reason, k, j = self.tcp:send(__dataPack, i + 1, _len)
    end
    if reason == STATUS_CLOSED or reason == STATUS_TIMEOUT then
        self:close()
        if self.isConnected then
            self:_onDisconnect()
        else 
            self:_connectFailure()
        end
    end
end

function SocketTCP:close( ... )
    --echoInfo("%s.close", self.name)
    self.tcp:close();
    if self.connectTimeTickScheduler then scheduler.unscheduleGlobal(self.connectTimeTickScheduler) end
    if self.tickScheduler then scheduler.unscheduleGlobal(self.tickScheduler) end
    if self.connectTimeTickScheduler then scheduler.unscheduleGlobal(self.connectTimeTickScheduler) end
    self:dispatchEvent({name=SocketTCP.EVENT_CLOSE})
end

-- disconnect on user's own initiative.
function SocketTCP:disconnect()
    self:_disconnect()
    self.isRetryConnect = false -- initiative to disconnect, no reconnect.
end

--------------------
-- private
--------------------

--- When connect a connected socket server, it will return "already connected"
-- @see: http://lua-users.org/lists/lua-l/2009-10/msg00584.html
function SocketTCP:_connect()
    local __succ, __status = self.tcp:connect(self.host, self.port)
    -- print("SocketTCP._connect:", __succ, __status)
    return __succ == 1 or __status == STATUS_ALREADY_CONNECTED
end

function SocketTCP:_disconnect()
    self.isConnected = false
    self.buf = ""
    self.msgLen = 0
    self.tcp:shutdown()
    self:dispatchEvent({name=SocketTCP.EVENT_CLOSED})
end

function SocketTCP:_onDisconnect()
    --echoInfo("%s._onDisConnect", self.name);
    self.buf = ""
    self.msgLen = 0
    self.isConnected = false
    self:dispatchEvent({name=SocketTCP.EVENT_CLOSED})
    self:_reconnect();
end

-- connecte success, cancel the connection timerout timer
function SocketTCP:_onConnected()
    --echoInfo("%s._onConnectd", self.name)
    self.isConnected = true
    self:dispatchEvent({name=SocketTCP.EVENT_CONNECTED})
    if self.connectTimeTickScheduler then scheduler.unscheduleGlobal(self.connectTimeTickScheduler) end
    self.buf = ""
    self.msgLen = 0

    local receive_msg_part
    receive_msg_part = function()
        local tmpLen = string.len(self.buf)

        --print("msgLen:", msgLen, "tmpLen:", tmpLen, "---:", msgLen - tmpLen, "type:", type(msgLen-tmpLen))
        local packet, status, partial = self.tcp:receive(self.msgLen - tmpLen)	-- read the package body
        --print("receive, packet:", packet, "status:", status, "partial:", partial)
        --if packet then
            --print( "len:", string.len(packet))
        --end

        if status == STATUS_CLOSED or status == STATUS_NOT_CONNECTED then
            return 2
        end

        -- 没有收到内容
        if (not (packet and string.len(packet) > 0)) and
            (not (partial and string.len(partial) >0)) then
            return 0
        end

        if packet and string.len(packet) > 0 then
            self.buf = self.buf .. packet
        end
        if partial and string.len(partial) > 0 then
            self.buf = self.buf .. partial
        end

        tmpLen = string.len(self.buf)

        if tmpLen == self.msgLen then
            return 1; 
        elseif tmpLen > 0 and tmpLen < self.msgLen then
            return receive_msg_part();
        else --  /* tmpLen > self.msgLen */
            return 2
        end
    end

    local receive_msg, receive_head, receive_body

    receive_head = function()
        local ret = receive_msg_part()
        if ret == 1 then
            local byteArr = cc.utils.ByteArray.new(cc.utils.ByteArray.ENDIAN_BIG)
            byteArr:writeStringBytes(self.buf)
            byteArr:setPos(1)
            self.msgLen = byteArr:readInt()
            self.buf = ""
            receive_msg = receive_body
            return receive_msg()
        else 
            return ret
        end
    end

    receive_body = function()
        local ret = receive_msg_part()
        if ret == 1 then
            local buf = self.buf
            self:dispatchEvent({name=SocketTCP.EVENT_DATA, buf=buf})
            self.buf = ""
            self.msgLen = self.packet
            receive_msg = receive_head
            return 0
        else 
            return ret
        end
    end

    self.buf = ""
    self.msgLen = self.packet
    receive_msg = receive_head

    local __tick = function()
        while true do
            local ret = receive_msg()
            if ret == 2 then
                self:close()
                if self.isConnected then
                    self:_onDisconnect()
                else 
                    self:_connectFailure()
                end
                return
            elseif ret == 0 then -- receive nothing
                return
            end
        end
    end
    -- start to read TCP data
    self.tickScheduler = scheduler.scheduleGlobal(__tick, SOCKET_TICK_TIME)
end

function SocketTCP:_connectFailure(status)
    --echoInfo("%s._connectFailure", self.name);
    self:dispatchEvent({name=SocketTCP.EVENT_CONNECT_FAILURE})
    self:_reconnect();
end

-- if connection is initiative, do not reconnect
function SocketTCP:_reconnect(__immediately)
    if not self.isRetryConnect then return end
    echoInfo("%s._reconnect", self.name)
    if __immediately then self:connect() return end
    if self.reconnectScheduler then scheduler.unscheduleGlobal(self.reconnectScheduler) end
    local __doReConnect = function ()
        self:connect()
    end
    self.reconnectScheduler = scheduler.performWithDelayGlobal(__doReConnect, SOCKET_RECONNECT_TIME)
end

return SocketTCP
