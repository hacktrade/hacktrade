--[[
	Функции для расчета греков и теоретической цены опционов
   	Формулы взяты отсюда:
   	http://en.wikipedia.org/wiki/Black%96Scholes
   	http://en.wikipedia.org/wiki/Greeks_%28finance%29

   На основе скрипта Sergey Gorokhov источник https://forum.quik.ru/messages/forum10/message7203/topic748/#message7203
]]
-------------------------------НАСТРОЙКИ-------------------------------
local RiskFree=0 -- безрисковая ставка %, Указывается вручную от 0 до 100
local YearLen=365.0 -- Число дней в году

-------------------------------ФУНКЦИИ------------------------------------------------------------------

function N(x) -- Нормальное среднее
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

function pN(x) -- производная от функции нормального среднего
   return math.exp(-0.5 * x * x) / math.sqrt(2 * math.pi)
end

function Greeks(tmpParam) -- возвращает таблицу греков
	--[[  таблица параметров:
		optiontype			тип опциона
		strike				цена исполнения опциона
		settleprice			текущая цена базового актива
		volatility			волатильность базового актива
		DAYS_TO_MAT_DATE	число дней до экспирации
	]]

	local b = tmpParam.volatility / 100 											-- "b" волатильность доходности (квадратный корень из дисперсии) базисной акции.
	local S = tmpParam.settleprice 													-- "S" текущая цена базисной акции;
	local Tt = tmpParam.DAYS_TO_MAT_DATE / YearLen 									-- "T-t" время до истечения срока опциона (период опциона);
	local K =  tmpParam.strike 														-- "K" цена исполнения опциона;
	local r = RiskFree 																-- "r" безрисковая процентная ставка;
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


   if tmpParam.optiontype == "Call" then
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

function TheorPrice(tmpParam) -- возвращает теоретическую цену опциона
	--[[  таблица параметров:
		optiontype			тип опциона
		strike				цена исполнения опциона
		settleprice			текущая цена базового актива
		volatility			волатильность базового актива
		DAYS_TO_MAT_DATE	число дней до экспирации
	]]
	local price = 0
	local b = tmpParam.volatility / 100 											-- "b" волатильность доходности (квадратный корень из дисперсии) базисной акции.
	local S = tmpParam.settleprice 													-- "S" текущая цена базисной акции;
	local Tt = tmpParam.DAYS_TO_MAT_DATE / YearLen 									-- "T-t" время до истечения срока опциона (период опциона);
	local K =  tmpParam.strike 														-- "K" цена исполнения опциона;
	local r = RiskFree 																--"r" безрисковая процентная ставка;
	local d1 = (math.log(S / K) + (r + b * b * 0.5) * Tt) / (b * math.sqrt(Tt))
	local d2 = d1-(b * math.sqrt(Tt))
	local e = math.exp(-1 * r * Tt)
--   log:debug("tmpParam.optiontype="..tmpParam.optiontype)
    if tmpParam.optiontype == "Call" then
    	price = S * N(d1) - K * e * N (d2)											-- теоретическая цена опциона call
    else
    	price = K * e * N(-1 * d2) - S * N (-1 * d1)								-- теоретическая цена опциона put
    end

	return price

end


function round(num, idp) -- округляет до указанного количества знаков
   local mult = 10^(idp or 0)
   return math.floor(num * mult + 0.5) / mult
end


