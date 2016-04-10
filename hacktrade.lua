--[[
[   HackTrade version 1.4
[   Nano-framework for HFT-robots development.
[   -----------------------------------------------------------
[   © 2014 Denis Kolodin
[
[]]--

--[[
[   Releases:
[     1.3.1 - Bids in quotes 2 reverses. Fix bugs.
[
[
[
[
[]]--

--[[
[   What to do?!
[     - save and restoring state (is it needed?)
[     - stop working during clearing time (global variable, use OnConnected)
[
[]]--


--[[ SERVICE FUNCTIONS ]]--
function string.starts(source, starts)
   return string.sub(source, 1, string.len(starts)) == starts
end

function string.ends(source, ends)
   return End=='' or string.sub(source,-string.len(ends)) == ends
end

function table.reverse(tab)
  local size = #tab
  local ntab = {}
  for i, v in ipairs(tab) do
    ntab[size-i+1] = v
  end
  return ntab
end

function table.transform(tab, felem)
  local ntab = {}
  for idx = 1, #tab do
    ntab[idx] = felem(tab[idx])
  end
  return ntab
end

Trade = coroutine.yield

-- OOP support
__object_behaviour = {
  __call = function(meta, o)
    if meta.__index == nil then
      setmetatable(o, {__index = meta})
    else
      setmetatable(o, meta)
    end
    if meta.init ~= nil then
      meta.init(o)
    end
    return o
  end
}

function round(num, idp)
  local mult = 10 ^ (idp or 0)
  return math.floor(num * mult + 0.5) / mult
end

--[[ MARKET DATA SOURCE ]]--
MarketData = {}
function MarketData._pvconverter(elem)
  local nelem = {}
  nelem.price = tonumber(elem.price)
  nelem.volume = tonumber(elem.volume)
  return nelem
end
function MarketData:init()
  log:trace("MarketData created: " .. self.market .. " " .. self.ticker)
end
function MarketData:__index(key)
  if MarketData[key] ~= nil then
    return MarketData[key]
  end
  --[[ DEPRECATED: Lazy value support. Don't need it.
  if string.starts(key, "lazy") then
    lazy, key = string.match(key, "([^_]+)_([^_]+)")
    return function() return self[key] end
  end
  ]]--
  if key == "bids" then
    local data = getQuoteLevel2(self.market, self.ticker).bid
    data = table.reverse(data) -- Reverse for normal order (not alphabet)!
    data = table.transform(data, self._pvconverter)
    return data or {}
  elseif key == "offers" then
    local data = getQuoteLevel2(self.market, self.ticker).offer
    data = table.transform(data, self._pvconverter)
    return data or {}
  end
  local param = getParamEx(self.market, self.ticker, key)
  if tonumber(param.param_type) < 3 then
    return tonumber(param.param_value)
  else
    return param.param_value
  end
end
function MarketData:fit(price)
  local step = feed.sec_price_step
  local result = math.floor(price / step) * step
  return round(result, self.sec_scale)
end
function MarketData:move(price, val)
  local step = feed.sec_price_step
  local result = (math.floor(price / step) * step) + (val * step)
  return round(result, self.sec_scale)
end
setmetatable(MarketData, __object_behaviour)


--[[ HISTORY DATA SOURCE ]]--
History = {}
function History:__index(key)
  if History[key] ~= nil then
    return History[key]
  end
  if key < 0 then
    key = #self + key + 1
  end
  return self[key]
end
setmetatable(History, __object_behaviour)

-- You can access by closes_0, values, values_1
Indicator = {}
function Indicator:init()
  log:trace("Indicator created with tag: " .. self.tag)
end
function Indicator:__index(key)
  local extractor = nil
  if type(key) == "number" then
    extractor = key
    key = "closes_0"
  end
  local line = key:match("%d+")
  local field = key:match("%a+")
  if line == nil then
    line = 0
  end
  local candles = getNumCandles(self.tag)
  local data, n, b = getCandlesByIndex(self.tag, tonumber(line), 0, candles)
  if n == 0 then
    log:fatal("Can't load data for chart with tag: "..self.tag)
  end
  if field ~= nil then
    field = field:sub(0, -2)
    if field == "value" then
      field = "close"
    end
    for idx = 1, #data do
      data[idx] = data[idx][field]
    end
  end
  local result = History(data)
  if extractor ~= nil then
    return result[extractor]
  else
    return result
  end
end
setmetatable(Indicator, __object_behaviour)


--[[ EXECUTION SYSTEM ]]--
SmartOrder = {
  -- 666 - Warning! This number uses for cancelling!
  lower = 1000,
  upper = 10000,
  pool = {}
}
function SmartOrder:__index(key)
  if SmartOrder[key] ~= nil then
    return SmartOrder[key]
  end
  --[[
  for k, v in pairs(self) do
    if key == k then
      return v
    end
  end
  ]]--
  -- Dynamic fields have to be calculated!
  if key == "remainder" then
    return (self.planned - self.position)    
  end
  if key == "filled" then
    return (self.planned - self.position) == 0  
  end
  return nil
end
function SmartOrder:init()
  math.randomseed(os.time())
  for i = self.lower, self.upper do
    local key = math.random(self.lower, self.upper)
    -- Store unique number of transaction which can be used as pool for processing
    if SmartOrder.pool[key] == nil then
      SmartOrder.pool[key] = self
      self.trans_id = key
      break
    end
  end
  self.position = 0
  self.planned = 0
  self.order = nil
  log:trace("SmartOrder created with trans_id: " .. self.trans_id)
end
function SmartOrder:destroy()
  SmartOrder.pool[self.trans_id] = nil
end
function SmartOrder:update(price, planned)
  if price ~= nil then
    self.price = price
  end
  if planned ~= nil then
    self.planned = planned
  end
end
function SmartOrder:process()
  log:debug("----------------------------------------------------------------------------------------------------")
  log:debug("Processing SmartOrder >> " .. self.trans_id)
  local order = self.order
  if order ~= nil then
    log:debug("Parameters >> ".."price="..tostring(self.price).." planned="..self.planned.." position="..self.position.." order_qty="..order.quantity)
    local cancel = false
    if order.price ~= self.price then
      cancel = true
      log:debug("NEW PRICE="..self.price)
    end
    local filled = order.filled * order.sign
    --log:debug("Difference >> planned=" .. self.planned .. " position=" .. self.position .. " order_qty=" .. order.quantity)
    if self.planned - self.position - order.quantity ~= 0 then
      cancel = true
    end
    if order.active == false then
      -- Считаем после установки флага!!!
      filled = order.filled * order.sign
      self.position = self.position + filled
      self.order = nil
    else
      if cancel then
        if self.order.number ~= nil then
          if self.order.cancelled ~= nil then
            if (os.time() - self.order.cancelled) > 5 then
              self.order.cancelled = nil
            end
          else
            local result = sendTransaction({
              ACCOUNT=self.account,
              CLIENT_CODE=self.client,
              CLASSCODE=self.market,
              SECCODE=self.ticker,
              TRANS_ID="666",
              ACTION="KILL_ORDER",
              ORDER_KEY=tostring(self.order.number),
            })
            if result == "" then
              self.order.cancelled = os.time()
            end
            log:debug("Kill order!")
          end
        end
      end
    end
  else
    log:debug("Parameters >> ".."price="..tostring(self.price).." planned="..self.planned.." position="..self.position.." order_qty=nil")
    local diff = self.planned - self.position
    if diff ~= 0 then
      if self.order == nil then
        local absdiff = math.abs(diff)
        local result = sendTransaction({
          ACCOUNT=self.account,
          CLIENT_CODE=self.client,
          CLASSCODE=self.market,
          SECCODE=self.ticker,
          TYPE="L",
          TRANS_ID=tostring(self.trans_id),
          ACTION="NEW_ORDER",
          OPERATION=(diff > 0 and "B") or "S",
          PRICE=tostring(self.price),
          QUANTITY=tostring(absdiff)
        })

        if result == "" then
          self.order = {
            sign = diff / absdiff,
            price = self.price,
            quantity = diff,
            active = true,
            filled = 0,
          }
          log:debug("NEW_ORDER  >> "..self.market.." "..self.ticker.." price="..tostring(self.price).." qty="..tostring(absdiff))
        else       
          log:debug("New order ERROR: "..result)
        end  
      end
    end
  end
end
setmetatable(SmartOrder, __object_behaviour)


--[[ LOGGING ]]--
log = {
    logfile = nil,
    loglevel = -1,
    loglevels = {
        [-1] = 'Debug',
        [ 0] = 'Trace',
        [ 1] = 'Info',
        [ 2] = 'Warning',
        [ 3] = 'Error',
    }
}
function log:log(log_text, log_level)
  if (log_level >= self.loglevel) then
    local msg = string.format("[%s] %s: %s\n", os.date(), self.loglevels[log_level], log_text)
    if (log_level > 0) then
      message(msg, log_level)
    end
    self.logfile:write(msg)
    self.logfile:flush()
  end
end
function log:debug(t)
  self:log(t, -1)
end
function log:trace(t)
  self:log(t, 0)
end
function log:info(t)
  self:log(t, 1)
end
function log:warning(t)
  self:log(t, 2)
end
function log:error(t)
  self:log(t, 3)
end
function log:fatal(t)
  self:error(t)
  error(t)
end

--[[ MAIN LOOP ]]--
working = true
function main()
  --create_table()
  log:trace("Robot started")
  if Start ~= nil then
    Start()
  end
  if Robot ~= nil then
    local routine = coroutine.create(Robot)
    while working do
      local res, errmsg = coroutine.resume(routine)
      if res == false then
        log:fatal("Broken coroutine: " .. errmsg)
      end
      if coroutine.status(routine) == "dead" then
        log:trace("Robot routine finished")
        break
      end
      -- Orders processing calls after every coroutine iteration
      for trans_id, smartorder in pairs(SmartOrder.pool) do
        smartorder:process()
      end
    end
  end
  log:trace("Robot stopped")
  if Stop ~= nil then
    Stop()
  end
  io.close(log.logfile)
end

--[[ TRANSACTION CALLBACK ]]--
function OnTransReply(trans_reply)
  local key = trans_reply.trans_id
  local executor = SmartOrder.pool[key]
  if executor ~= nil then
    if trans_reply.status == 3 then
      executor.order.number = trans_reply.ordernum
    else
      executor.order = nil
    end
  end
end

--[[ ORDERS CALLBACK ]]--
function OnOrder(order)
  local key = order.trans_id
  local executor = SmartOrder.pool[key]
  -- There isn't order if was executed imidiately!
  if executor ~= nil and executor.order ~= nil then
    executor.order.filled = order.qty - order.balance
    if (order.flags % 2) == 0 then
      executor.order.active = false
    end
  end
end
withgui = false
--[[ INIT CALLBACK ]]--
function OnInit(path)
  -- Only there it's possible to take path
  log.logfile = io.open(path..'.log', 'w')
  -- Table creation
  if withgui == true then
    local table_id = AllocTable()
    if CreateWindow(table_id) == 1 then
      log:trace("SmartOrders table created, id=" .. table_id)
      SetWindowCaption(table_id, "SmartOrders [" .. path .. "]")
      AddColumn(table_id, "trans_id", nil, QTABLE_INT_TYPE, 10)
      AddColumn(table_id, "status", nil, QTABLE_STRING_TYPE, 10)
    else
      log:fatal("SmartOrders table not created!" .. table_id)
    end
    SmartOrder.table = table_id
  end
end


--[[ END CALLBACK ]]--
function OnStop(stop_flag)
  working = false
  if withgui == true then
    DestroyTable(SmartOrder.table)
  end
end
