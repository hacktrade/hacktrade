dofile("../hacktrade.lua")

function Robot()

    feed = MarketData{
        market="",
        ticker=""
    }

    order = SmartOrder{
        account="",
        client="",
        market="",
        ticker="",
    }

    ind = Indicator{
        tag=""
    }

    while true do
        Trade()
    end
end
