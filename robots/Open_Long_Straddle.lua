-- Робот “Открытие стредла” ver 0.4
-- открывает синтетический стредл на опционах CALL

--используем фреймворк "HackTrade" https://github.com/hacktrade/hacktrade.git
dofile("../hacktrade.lua")

require("Black-Scholes")			-- функции расчета теоретической цены и греков
require("utils")					-- вспомогательные функции для работы со строками 

function Robot()

--================= ВХОДЯЩИЕ ПАРАМЕТРЫ ======================

	local ACCOUNT ="410097K"		-- торговый счет
	local FUT_CLASS = "SPBFUT"		-- класс FORTS
	local OPT_CLASS = "SPBOPT"		-- класс опционы FORTS
	local FUT_TICKER = "RIM6"		-- код бумаги фьючерса
	local OPT_TICKER = "RI85000BF6"	-- код бумаги опциона
	local MAX_OPT_QTY = 52			-- максимальное количество опционов для покупки
	local OPT_LOT = 2				-- количество лотов для заявки на покупку опционов
	local MAX_LAG = 2				-- максимальное превышение цены над теоретической ценой (указывается в ШАГАХ ЦЕНЫ)
	local MAX_VOLA = 35.5				-- максимальная волатильность опционов, по которой мы готовы покупать, указывается в процентах
	local FIX_VOLA = 35 			-- желательная волатильность, указывается в процентах
    local CONST = 1					-- отступ от лучшей цены для заявок (указывается в ШАГАХ ЦЕНЫ)
	local SLACK = 1					-- люфт - разница между текущей ценой заявки и новой расчетной ценой. Если разница меньше, чем люфт, то имеющуюся заявку не меняем.

	local COMMENT = "str"			-- комментарий к заявке для "Истории позиций"

	local SLEEP_WITH_ORDER = 1000	-- время ожидания исполнения выставленного ордера до пересчета теоретической цены (в миллисекундах)
	local SLEEP_WO_ORDER = 100		-- время ожидания после снятия ордера (в миллисекундах)

    local OPEN_POSITIONS_FILE = "C:\\QUIK_OpenBroker\\QPILE\\ОткрытыеПозиции.csv"  -- путь к файлу, где храняться открытые позиции
     
--======== КОНЕЦ РАЗДЕЛА ВХОДЯЩИХ ПАРАМЕТРОВ ==================

-- Читаем файл с открытыми позициями OPEN_POSITIONS_FILE, чтобы определить нашу начальную позицию, которую мы уже набрали ранее. Ориентируемся на поле "Комментарий"
    local parameters = {separator = ";",header = true}

    local csv = require("csv")
    local f,err = csv.open(Utf8ToAnsi(OPEN_POSITIONS_FILE),parameters)     

    if f == nil then -- если не смогли открыть файл с Историей позиций
    	if err then 
    		log:trace("Failed to open \"OPEN_POSITIONS_FILE\" file! "..err) 
    		message("Failed to open \"OPEN_POSITIONS_FILE\" file! "..err,2)
    	end
    	return 
    end 	

    for row in f:lines() do
        if row[Utf8ToAnsi("Комментарий")] == COMMENT and row[Utf8ToAnsi("Код класса")] == OPT_CLASS and row[Utf8ToAnsi("Код бумаги")] == OPT_TICKER then
            if row[Utf8ToAnsi("Операция")] == "BUY" then
                opt_start_position = row[Utf8ToAnsi("Кол-во")]
            else
                opt_start_position = 0-row[Utf8ToAnsi("Кол-во")]
            end
        elseif row[Utf8ToAnsi("Комментарий")] == COMMENT and row[Utf8ToAnsi("Код класса")] == FUT_CLASS and row[Utf8ToAnsi("Код бумаги")] == FUT_TICKER then
            if row[Utf8ToAnsi("Операция")] == "BUY" then
                fut_start_position = row[Utf8ToAnsi("Кол-во")]
            else
                fut_start_position = 0-row[Utf8ToAnsi("Кол-во")]
            end
        end 
    end
-- начальную позицию определили


	local working = true
    local vola
    local best_offer
    local theor_price_calc
	local theor_price_fix
    local theor_price_quik
    local opt_qty = 0				-- начальная позиция по опционам

    opt_feed = MarketData{			-- читаем текущие параметры по опциону
        market=OPT_CLASS,
        ticker=OPT_TICKER
    }

    fut_feed = MarketData{			-- читаем текущие параметры по фьючерсу
        market=FUT_CLASS,
        ticker=FUT_TICKER
    }

    opt_order = SmartOrder{			-- создаем умную заявку для опциона
        account=ACCOUNT,
        client=ACCOUNT.."//"..COMMENT,
        market=OPT_CLASS,
        ticker=OPT_TICKER
    }

    fut_order = SmartOrder{			-- создаем умную заявку для фьючерса
        account=ACCOUNT,
        client=ACCOUNT.."//"..COMMENT,
        market=FUT_CLASS,
        ticker=FUT_TICKER
    }

    opt_order.position = opt_start_position
    opt_qty = opt_start_position
    opt_order:update(0, opt_qty)

    fut_order.position = fut_start_position
    fut_qty = fut_start_position
    fut_order:update(0,fut_qty)

    Trade()

    local optionbase=getParamEx(OPT_CLASS,OPT_TICKER,"optionbase").param_image
    local optiontype=getParamEx(OPT_CLASS,OPT_TICKER,"optiontype").param_image

    --local step=getParamEx(OPT_CLASS,OPT_TICKER,"SEC_PRICE_STEP,").param_value
    local step=opt_feed.SEC_PRICE_STEP
	--log:debug("step="..step)

    log:debug("optionbase= "..optionbase.." optiontype= "..optiontype)
    log:debug ("opt_start_position="..tostring(opt_start_position).." fut_start_position="..tostring(fut_start_position))
    log:debug("MAX_VOLA="..MAX_VOLA.." FIX_VOLA="..FIX_VOLA)

--[[
    ind = Indicator{
        tag=""
    }
  ]]
 
    while working do

    	opt_qty = opt_qty + OPT_LOT 					-- увеличиваем позицию по опциону
		local new_price = 0
		local order_price = 0

		local i = 0

        repeat

			i = i + 1
	    	vola = opt_feed.volatility               	-- текущая волатильность опциона из QUIK

            local tmpParam = {
                    ["optiontype"] = optiontype,                                                                -- тип опциона
                    ["settleprice"] = getParamEx(FUT_CLASS,FUT_TICKER,"settleprice").param_value+0,             -- текущая цена фьючерса
                    ["strike"] = getParamEx(OPT_CLASS,OPT_TICKER,"strike").param_value+0,                       -- страйк опциона
                    ["volatility"] = FIX_VOLA,                                                                  -- волатильность опциона: берём желаемую FIX_VOLA
                    ["DAYS_TO_MAT_DATE"] = getParamEx(OPT_CLASS,OPT_TICKER,"DAYS_TO_MAT_DATE").param_value+0    -- число дней до экспирации опциона
            }

            theor_price_fix = TheorPrice (tmpParam)                                                         	-- наша теоретическая цена
            theor_price_fix = theor_price_fix - math.fmod(theor_price_fix,step) 								-- округляем до шага цены вниз

            local tmpParam = {
                    ["optiontype"] = optiontype,                                                                -- тип опциона
                    ["settleprice"] = getParamEx(FUT_CLASS,FUT_TICKER,"settleprice").param_value+0,             -- текущая цена фьючерса
                    ["strike"] = getParamEx(OPT_CLASS,OPT_TICKER,"strike").param_value+0,                       -- страйк опциона
                    ["volatility"] = vola, 													                    -- волатильность опциона: берём волатильность из QUIK
                    ["DAYS_TO_MAT_DATE"] = getParamEx(OPT_CLASS,OPT_TICKER,"DAYS_TO_MAT_DATE").param_value+0    -- число дней до экспирации опциона
            }

            theor_price_calc = TheorPrice (tmpParam)                                                         	-- наша теоретическая цена
            theor_price_calc = theor_price_calc - math.fmod(theor_price_calc,step) 								-- округляем до шага цены вниз


		    best_offer = opt_feed.offers[1].price --потом убрать, нужно только для лога

		    log:debug ("==============================================================================================#"..i.."=")
			log:debug ("vola="..vola.." max_vola="..MAX_VOLA.." best_offer="..best_offer.." theor_price_fix="..theor_price_fix.." theor_price_calc="..theor_price_calc.." quik_theor_price="..opt_feed.theorprice.." opt_qty="..opt_qty)

		    if vola > MAX_VOLA then                                  	-- если текущая волатильность слишком высокая, то используем теоретическую цену, рассчитанную
																		-- на базе желаемой волатильности по формуле Блека-Шоулза
                --opt_order:update(theor_price_fix, opt_qty)            	-- выставляем заявку по нашей теоретической цене
				new_price = theor_price_fix
                log:debug("decision:1 >> theor_price_fix")
		    else
		    	best_offer = opt_feed.offers[1].price   			 	-- минимальная цена предложения BEST_OFFER

                if best_offer < theor_price_calc then

                    --opt_order:update(best_offer + CONST * step, opt_qty)
					new_price = best_offer + CONST * step
                    log:debug("decision:2 >> best_offer + CONST")

                elseif best_offer == theor_price_calc then

					--opt_order:update(best_offer, opt_qty)
					new_price = best_offer
                    log:debug("decision:3 >> best_offer")

                elseif best_offer > theor_price_calc then

                    if best_offer > theor_price_calc + MAX_LAG * step then

                        --opt_order:update(theor_price_calc, opt_qty)
						new_price = theor_price_calc
                        log:debug("decision:4 >> theor_price_calc")

                    else
                        --opt_order:update(best_offer - CONST * step, opt_qty)
						new_price = best_offer - CONST * step
                        log:debug("decision:5 >> best_offer - CONST")
                    end
                end

		    end

			if math.abs(order_price - new_price) > SLACK*step then
				log:debug("UPDATE >> new_price="..new_price.." order_price="..order_price)
				order_price = new_price
				opt_order:update(order_price, opt_qty)
			else
				log:debug("Nothing to do >> new_price="..new_price.." order_price="..order_price)
			end

	        Trade()

	        log:debug("----------------------------------------------------------------------------------------------------")

	        if opt_order.order ~= nil and opt_order.order.price == order_price then
	        	log:debug("SLEEP_WITH_ORDER")
	        	sleep (SLEEP_WITH_ORDER)
	        else
	        	log:debug("SLEEP_WO_ORDER")	        	
	        	sleep (SLEEP_WO_ORDER)
	        end

        until opt_order.filled 									-- работаем, пока не купим очередной лот опционов

        repeat

        	fut_qty = 0-math.floor(opt_order.position/2)		-- для стредла количество фьючерсов в два раза меньше количества опционов
        	fut_order:update(fut_feed.offers[1].price,fut_qty)	-- ставим заявку на продажу фьючерса по лучшей цене

	        Trade()

	        if fut_order.order ~= nil and fut_order.order.price == fut_feed.offers[1].price then
	        	sleep (SLEEP_WITH_ORDER)
	        else
	        	sleep (SLEEP_WO_ORDER)
	        end

        until fut_order.filled 									-- работаем до тех пор, пока не купим фьючи

        if opt_order.position >= MAX_OPT_QTY then  				-- стредл куплен, завершаем работу
        	working = false
        	log:trace("Straddle opened >> "..OPT_TICKER..": +"..opt_order.position.." and "..FUT_TICKER..": -"..fut_order.position)
        end

    end
end
