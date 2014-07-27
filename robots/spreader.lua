dofile("../hacktrade.lua")

function Robot()

    feed = MarketData{
        market="QJSIM",
        ticker="SBER",
    }

    order = SmartOrder{
        account="NL0011100043",
        client="74924",
        market="QJSIM",
        ticker="SBER",
    }
    
    
    while working do
      repeat
        order:update(feed.bids[1].price, 3)
        Trade()
      until order.filled      
      repeat
        order:update(feed.offers[1].price, 0)
        Trade()
      until order.filled
    end
end