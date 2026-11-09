%dw 2.0
import fail from dw::Runtime
output application/json
---
if (payload.name == "alisha")
    payload ++ { student: "kannan" }
else
    fail("Invalid name '$(payload.name default "null")'. Expected 'alisha'.")
