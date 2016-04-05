-- Робот “Открытие стредла” ver 0.2
-- открывает синтетический стредл на опционах CALL

--используем фреймворк "HackTrade" https://github.com/hacktrade/hacktrade.git
dofile("../hacktrade.lua")
require("Black-Scholes")


function Robot()

-- Входящие параметры
	local ACCOUNT ="410097K"		-- торговый счет
	local FUT_CLASS = "SPBFUT"		-- класс FORTS
	local OPT_CLASS = "SPBOPT"		-- класс опционы FORTS
	local FUT_TICKER = "RIM6"		-- код бумаги фьючерса
	local OPT_TICKER = "RI85000BF6"	-- код бумаги опциона
	local MAX_OPT_QTY = 4			-- максимальное количество опционов для покупки
	local OPT_LOT = 2				-- количество лотов для заявки на покупку опционов
	local MAX_LAG = 2				-- максимальное превышение цены над теоретической ценой (указывается в ШАГАХ ЦЕНЫ)
	local MAX_VOLA = 35.5			-- максимальная волатильность опционов, по которой мы готовы покупать, указывается в процентах
	local FIX_VOLA = 35 			-- желательная волатильность, указывается в процентах
    local CONST = 1					-- отступ от лучшей цены для заявок (указывается в ШАГАХ ЦЕНЫ)
	local COMMENT = "Straddle"		-- комментарий к заявке для "Истории позиций"

	local SLEEP_WITH_ORDER = 60000	-- время ожидания исполнения выставленного ордера до пересчета теоретичской цены (в миллисекундах)
	local SLEEP_WO_ORDER = 100		-- время ожидания после снятия ордера (в миллисекундах)

-- Конец раздела с входящими параметрами

	local working = true
    local vola
    local best_offer
    local theor_price
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

    local optionbase=getParamEx(OPT_CLASS,OPT_TICKER,"optionbase").param_image
    local optiontype=getParamEx(OPT_CLASS,OPT_TICKER,"optiontype").param_image
    
    --local step=getParamEx(OPT_CLASS,OPT_TICKER,"SEC_PRICE_STEP,").param_value
    local step=opt_feed.SEC_PRICE_STEP
	--log:debug("step="..step)
	
    log:debug("optionbase= "..optionbase.." optiontype= "..optiontype)
    log:debug("MAX_VOLA="..MAX_VOLA.." FIX_VOLA="..FIX_VOLA)

--[[
    ind = Indicator{
        tag=""
    }
  ]]

    while working do

    	opt_qty = opt_qty + OPT_LOT 					-- увеличиваем позицию по опциону
		local i = 0

        repeat

			i = i + 1
	    	vola = opt_feed.volatility                -- текущая волатильность опциона

            local tmpParam = {
                    ["optiontype"] = optiontype,                                                                -- тип опциона
                    ["settleprice"] = getParamEx(FUT_CLASS,FUT_TICKER,"settleprice").param_value+0,             -- текущая цена фьючерса
                    ["strike"] = getParamEx(OPT_CLASS,OPT_TICKER,"strike").param_value+0,                       -- страйк опциона
                    ["volatility"] = FIX_VOLA,                                                                  -- волатильность опциона: берём желаемую FIX_VOLA
                    ["DAYS_TO_MAT_DATE"] = getParamEx(OPT_CLASS,OPT_TICKER,"DAYS_TO_MAT_DATE").param_value+0    -- число дней до экспирации опциона
            }

            theor_price = TheorPrice (tmpParam)                                                         -- наша теоретическая цена
            theor_price = theor_price - math.fmod(theor_price,step) 									-- округляем до шага цены вниз

		    best_offer = opt_feed.offers[1].price --потом убрать, нужно для лога

		    log:debug ("==============================================================================================#"..i.."=")
			log:debug ("vola="..vola.." max_vola="..MAX_VOLA.." best_offer="..best_offer.." theor_price="..theor_price.." quik_theor_price="..opt_feed.theorprice.." opt_qty="..opt_qty)

		    if vola > MAX_VOLA then                                  -- если текущая волатильность слишком высокая, то используем теоретическую цену, рассчитанную
		    	                                                     -- на базе желаемой волатильности по формуле Блека-Шоулза
                opt_order:update(theor_price, opt_qty)               -- выставляем заявку по нашей теоретической цене
                log:debug("decision:1 >> theor_price")
		    else
		    	best_offer = opt_feed.offers[1].price   			 -- минимальная цена предложения BEST_OFFER

                if best_offer < theor_price then

                    opt_order:update(best_offer + CONST * step, opt_qty)
                    log:debug("decision:2 >> best_offer + CONST")

                elseif best_offer == theor_price then

                    opt_order:update(best_offer, opt_qty)
                    log:debug("decision:3 >> best_offer")

                elseif best_offer > theor_price then

                    if best_offer > theor_price + MAX_LAG * step then

                        opt_order:update(theor_price, opt_qty)
                        log:debug("decision:4 >> theor_price")

                    else
                        opt_order:update(best_offer - CONST * step, opt_qty)
                        log:debug("decision:5 >> best_offer - CONST")
                    end
                end

		    end

	        Trade()

	        if opt_order.order ~= nil then
	        	sleep (SLEEP_WITH_ORDER)
	        else
	        	sleep (SLEEP_WO_ORDER)
	        end

        until opt_order.filled 									-- работаем, пока не купим очередной лот опционов

        repeat

        	fut_qty = 0-math.floor(opt_order.position/2)		-- для стредла количество фьючерсов в два раза меньше количества опционов
        	fut_order:update(fut_feed.offers[1].price,fut_qty)	-- ставим заявку на продажу фьючерса по лучшей цене

	        Trade()

	        if fut_order.order ~= nil then
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
