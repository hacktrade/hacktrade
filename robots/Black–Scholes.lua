--[[
Что делает:
   По Таблице текущих параметров строит таблицу опционов с расcчитанными греками
   Формулы взяты отсюда:
   http://en.wikipedia.org/wiki/Black%96Scholes
   http://en.wikipedia.org/wiki/Greeks_%28finance%29

Как использовать:
   откройте Таблицу Текущих Параметров (меню Таблицы -> Текущая Таблица)
   Укажите настройки, после чего, запустите скрипт (меню Таблицы - Lua - Доступные скрипты)
   чтобы сохранить в CSV файл, текущее состояние таблицы, нужно нажать комбинацию клавиш Ctrl+S файл сохраняется в папку со скриптом, с именем HHHMMDD.csv
]]
-------------------------------НАСТРОЙКИ-------------------------------
RiskFree=5 --безрисковая ставка %, Указывается вручную от 0 до 100

BaseClassCode = "SPBFUT" --Класс базового актива
ClassCode = "SPBOPT" --Класс опционов

--Список базовых активов, через запятую, по которым отображать опционы:
BaseSecList = "RIM6" --getClassSecurities(BaseClassCode) --все сразу

--Список опционов через запятую:
SecList = getClassSecurities(ClassCode) --все сразу

INTERVAL = 1000 --Интервал обновления таблицы

doLogging=false --включает запись в файл, формата csv.
log_file=getScriptPath() .. "\\Greek.csv" --путь к csv файлу

-----------------------------------------------------------------------

-------------------------------ТО ЧТО НИЖЕ, ТРОГАТЬ НЕ НАДО------------------------------------------------------------------
--Параметры таблицы
tbl = {
["caption"]="Greek",
[1]="Название",
[2]="Код опциона",
[3]="Тип опциона",
[4]="Баз. актив",
[5]="Расчетная цена",
[6]="Страйк",
[7]="Волатильность",
[8]="До исполнения",
[9]="Дельта",
[10]="Гамма(%)",
[11]="Тэта",
[12]="Вега",
[13]="Ро",
["t_id"]=0
}

abTable = {}
BaseCol = {}
Sec2row = {}
file = nil
Sep = ";"
YearLen=365.0 --Число дней в году
WORK = true
CALC = false
G_ROW = -1
if (BaseSecList == "") or (BaseSecList == nil) then
   BaseSecList = getClassSecurities(BaseClassCode)
end

if (SecList == "") or (SecList == nil) then
   SecList = getClassSecurities(ClassCode)
end

-------------------------------ФУНКЦИИ------------------------------------------------------------------
function Logging(str) --Пишет лог
   if file~=nil and doLogging then
      file:write(str .. "\n")
      file:flush()
   end
end

function N(x) --Нормальное среднее
    if (x > 10) then
      return 1
   elseif (x < -10) then
      return 0
   else
      local t = 1 / (1 + 0.2316419 * math.abs(x))
      local p = 0.3989423 * math.exp(-0.5 * x * x) * t * ((((1.330274 * t - 1.821256) * t + 1.781478) * t - 0.3565638) * t + 0.3193815)
      if x > 0 then
         p=1-p
      end
      return p
   end
end

function pN(x) --производная от функции нормального среднего
   return math.exp(-0.5 * x * x) / math.sqrt(2 * math.pi)
end

function Greek(tmpParam)
   local b = tmpParam.volatility / 100 --"b" волатильность доходности (квадратный корень из дисперсии) базисной акции.
   local S = tmpParam.settleprice --"S" текущая цена базисной акции;
   local Tt = tmpParam.DAYS_TO_MAT_DATE / YearLen --"T-t" время до истечения срока опциона (период опциона);
   local K =  tmpParam.strike --"K" цена исполнения опциона;
   local r = RiskFree --"r" безрисковая процентная ставка;
   local d1 = (math.log(S / K) + (r + b * b * 0.5) * Tt) / (b * math.sqrt(Tt))
   local d2 = d1-(b * math.sqrt(Tt))

local Delta = 0
local Gamma = 0
local Theta = 0
local Vega = 0
local Rho = 0

local e = math.exp(-1 * r * Tt)

   Gamma = pN(d1) / (S * b * math.sqrt(Tt))
   Vega = S * e * pN(d1) * math.sqrt(Tt)

   Theta = (-1 * S * b * e * pN(d1)) / (2 * math.sqrt(Tt))


   if tmpParam.Optiontype == "Call" then
      Delta = e * N(d1)
      Theta = Theta - (r * K * e * N(d2)) + r * S * e * N(d1)
      ----Theta = Theta - (r * K * e * N(d2))
      Rho = K * Tt * e * N(d2)
   else
      Delta = -1 * e * N(-1*d1)
      Theta = Theta + (r * K * e * N(-1 * d2)) - r * S * e * N(-1 * d1)
      ----Theta = Theta + (r * K * e * N(-1 * d2))
      Rho = -1 * K * Tt * e * N(-1 * d2)
   end


   return {
   ["Delta"] = Delta,
   ["Gamma"] = 100 * Gamma,
   ["Theta"] = Theta / YearLen,
   ["Vega"] = Vega / 100,
   ["Rho"] = Rho / 100
   }
end

function GetRow(ID,row) --возвращает строку таблицы
local rows, col = GetTableSize(ID)
local result = ""
if rows~=nil and row<=rows then
   for i=1,col do
      result=result..GetCell(ID,row,i).image .. Sep
   end
end
   return result
end

function CSV(T) --пишет таблицу в csv файл
   function FTEXT(V) --ПРОВЕРЯЕМ КОРРЕКТНОСТЬ КОЛИЧЕСТВА СИМОЛОВ ПЕРЕМЕННОЙ
      V=tostring(V)
      if (string.len(V)==1) or (string.len(V)==5) then
         V="0".. V
      end
      return V
   end
local temp = os.date("*t")
local Fname =getScriptPath() .. "\\" .. FTEXT(temp.year) .. FTEXT(temp.month) .. FTEXT(temp.day) .. ".csv"
   CSVFile = io.open(Fname, "w+")
   if CSVFile~=nil then
      local rows, col = GetTableSize(T.t_id)
      for i=1,col do --расставляем заголовки
         CSVFile:write(T[i] .. Sep)
      end
      CSVFile:write("\n")
      for i=1,rows do --пишем таблицу
         CSVFile:write(GetRow(T.t_id,i).."\n")
      end
      CSVFile:flush()
      CSVFile:close()
      message("Файл успешно сохранен:\n"..Fname, 1)
   else
      message("Ошибка при сохранении файла:\n"..Fname, 3)
   end
end

function round(num, idp) --округляет до указанного количества знаков
   local mult = 10^(idp or 0)
   return math.floor(num * mult + 0.5) / mult
end

function comma_value(n) --ставит разделители в числах
   local left,num,right = string.match(n,'^([^%d]*%d)(%d*)(.-)$')
   return left..(num:reverse():gsub('(%d%d%d)','%1 '):reverse())..right
end

function CreateDataSourceEX(Class,Sec,Par)
   local ds,err = CreateDataSource(Class, Sec, INTERVAL_TICK, Par)
   if ds==nil then
      message("Ошибка при получении параметра "..Par..":\n"..err, 3)
      return false
   else
      ds:SetEmptyCallback()
      while ds:Size()==0 do
         sleep(100)
      end
      return true
   end
end

function Stop()
   if doLogging then
      file:close()
   end
   WORK = false
end


function Calculate(row,do_calc)
if (row~=nil) and (row>=0) and (do_calc) then

         local T=BaseCol[row]

         local tmpParam ={
            ["Optiontype"] = T.Optiontype,
            ["settleprice"] = getParamEx(BaseClassCode,T.Optionbase,"settleprice").param_value+0,
            ["strike"] = getParamEx(ClassCode,T.SecCode,"strike").param_value+0,
            ["volatility"] = getParamEx(ClassCode,T.SecCode,"volatility").param_value+0,
            ["DAYS_TO_MAT_DATE"] = T.DAYS_TO_MAT_DATE
         }
         local tmpGreek = Greek(tmpParam)
         SetCell(tbl.t_id, row, 5, comma_value(tmpParam.settleprice), tmpParam.settleprice) -- "Расчетная цена",
         SetCell(tbl.t_id, row, 6, comma_value(tmpParam.strike), tmpParam.strike) --"Страйк",
         SetCell(tbl.t_id, row, 7, tostring(tmpParam.volatility), tmpParam.volatility) -- "Волатильность",
         SetCell(tbl.t_id, row, 8, tostring(tmpParam.DAYS_TO_MAT_DATE), tmpParam.DAYS_TO_MAT_DATE) --"До исполнения",
         SetCell(tbl.t_id, row, 9, tostring(round(tmpGreek.Delta,2)), tmpGreek.Delta) --"Дельта",
         SetCell(tbl.t_id, row, 10, tostring(round(tmpGreek.Gamma,4)), tmpGreek.Gamma) -- "Гамма(%)",
         SetCell(tbl.t_id, row, 11, tostring(round(tmpGreek.Theta,2)), tmpGreek.Theta) -- "Тэта",
         SetCell(tbl.t_id, row, 12, tostring(round(tmpGreek.Vega,2)), tmpGreek.Vega) -- "Вега",
         SetCell(tbl.t_id, row, 13, tostring(round(tmpGreek.Rho,2)), tmpGreek.Rho) -- "Ро",
         Logging(os.date().. Sep .. GetRow(tbl.t_id,row))
end
return false
end

-------------------------------Колбэки------------------------------------------------------------------
function f_cb(t_id,msg,par1,par2) --событие на нажатие клавиш
   if (msg==QTABLE_CHAR) and (par2==19) then --сохранить в CSV файл текущее состояние таблицы нужно нажать комбинацию клавиш Ctrl+S
      CSV(tbl)
   end
   if (msg==QTABLE_CLOSE) then --закрытие окна
      Stop()
   end
end

function OnStop()
   Stop()
   DestroyTable(tbl.t_id)
end

function OnInit()
local STR = ""
   if doLogging then
      file = io.open(log_file, "w+")
   end
   tbl.t_id = AllocTable()
   for i=1,table.maxn(tbl) do --добавляем колонки
      if i<=4 then
         AddColumn(tbl.t_id, i, tbl[i], true, QTABLE_CACHED_STRING_TYPE, string.len(tbl[i])*2)
      else
         AddColumn(tbl.t_id, i, tbl[i], true, QTABLE_DOUBLE_TYPE, 10)
      end
      if doLogging then
         STR=STR..tbl[i]..Sep
      end
   end
   Logging("Дата Время".. Sep .. STR)
   CreateWindow(tbl.t_id)
   SetWindowCaption(tbl.t_id,tbl.caption)
   SetTableNotificationCallback(tbl.t_id, f_cb)
end

function OnParam(class, sec)
if (class==ClassCode) and (WORK) and (string.find(SecList,sec)~=nil) then
   G_ROW = Sec2row[sec]
   if (G_ROW~=nil) and (G_ROW>=0) then
      Highlight(tbl.t_id, G_ROW, QTABLE_NO_INDEX, RGB(255,0,0), QTABLE_DEFAULT_COLOR, INTERVAL)
      CALC=true
   end
end
end

function main()

WORK = false
CALC=true
   for SecCode in string.gmatch(SecList, "([^,]+)") do --перебираем опционы по очереди.
            local Optionbase=getParamEx(ClassCode,SecCode,"optionbase").param_image
            local Optiontype=getParamEx(ClassCode,SecCode,"optiontype").param_image
            if (string.find(BaseSecList,Optionbase)~=nil) then
               local row = InsertRow(tbl.t_id,-1)
               local T={
                  ["Name"] = getSecurityInfo(ClassCode,SecCode).name,
                  ["SecCode"] = SecCode,
                  ["Optiontype"] = Optiontype,
                  ["Optionbase"] = Optionbase,
                  ["DAYS_TO_MAT_DATE"] = getParamEx(ClassCode,SecCode,"DAYS_TO_MAT_DATE").param_value+0
                  }
               BaseCol[row]=T
               --заполняем статичные параметры
               Sec2row[SecCode]=row
               SetCell(tbl.t_id, row, 1, BaseCol[row].Name) -- "Название опциона",
               SetCell(tbl.t_id, row, 2, BaseCol[row].SecCode) --"Код опциона",
               SetCell(tbl.t_id, row, 3, BaseCol[row].Optiontype) -- "Тип опциона",
               SetCell(tbl.t_id, row, 4, BaseCol[row].Optionbase) --"Баз. актив",
               --заказ данных
               CreateDataSourceEX(BaseClassCode,T.Optionbase,"settleprice")
               CreateDataSourceEX(ClassCode,T.SecCode,"strike")
               CreateDataSourceEX(ClassCode,T.SecCode,"volatility")

               --заполняем динамичные параметры
               CALC=Calculate(row,true)
            end
   end
WORK = true
while WORK do
   CALC=Calculate(G_ROW,CALC)
   sleep(INTERVAL)
end
end
