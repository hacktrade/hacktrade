dofile("../hacktrade.lua")

function Robot()

    feed = MarketData{
        market="QJSIM",
        ticker="SBER",
    }

    order = SmartOrder{
        account="NL0011100043",
        client="74808",
        market="QJSIM",
        ticker="SBER",
    }

    ind = Indicator{
        tag="MAVG",
    }
    
    size = 1

    while true do
        if feed.last > ind[-1] then
          order:update(feed.last, size)
        else
          order:update(feed.last, -size)
        end
        Trade()
    end
end
