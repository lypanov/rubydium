   # TODO for the moment this -> self!
   # (4 + 4 + 16 * (3 * 4)) # length, used, 16 * (id, type, value)
   def core_get_member dat, id
      idx_len  = 0; idx_used = 1
      used = dat.get_element(idx_used)
      idx = 0
      while idx < used
         pos = 2 + (idx * 3) + 0
         cur_id = dat.get_element(pos + 0)
         if cur_id == id
            return dat.get_element(pos + 2)
         end
         idx += 1
      end
      return -1
   end
   def core_set_member dat, id, val
      idx_len  = 0; idx_used = 1
      used = dat.get_element(idx_used)
      idx = 0
      while idx < used
         pos = 2 + (idx * 3) + 0
         cur_id = dat.get_element(pos + 0)
         if cur_id == id
            dat.set_element(pos + 0, id)
            dat.set_element(pos + 1, typeof(val))
            dat.set_element(pos + 2, val)
            return val
         end
         idx += 1
      end
      pos  = 2 + (3 * used)
      dat.set_element(pos + 0, id)
      dat.set_element(pos + 1, typeof(val))
      dat.set_element(pos + 2, val)
      used += 1
      dat.set_element(idx_used, used)
      val
   end
