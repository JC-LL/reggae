(memory_map soc

  (parameters
      (bus
        (frequency 100)
        (address_size 32)
        (data_size 32)
      )
      (range 0x0 0x201)
  )

  (zone ip_leds
    (range 0x0 0x0)
    (register value
      (address 0x0)
      (init 0x0)
    )
  )

  (zone ip_switches
    (range 0x1 0x1)
    (register value
      (address 0x1)
      (init 0x0)
    )
  )

  (zone bram1
    (range 0x2 0x101)
    (block_ram
      (size 256)
      (width 32)
      (range 0x2 0x101)
    )
  )

  (zone bram2
    (range 0x102 0x201)
    (block_ram
      (size 256)
      (width 32)
      (range 0x2 0x101)
    )
  )
)
