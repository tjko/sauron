/* Finding largest possible CIDRs that are part of a net but not of a subnet
 *
 * $Id:$
 */

create or replace function split_cidr4(p_cidr cidr, p_part integer) returns cidr as $$
-- IPv4. Returns a cidr whose address range corresponds to lower
-- or upper half of cidr that was given as parameter.
declare
  v_lower cidr;
begin

-- Increase mask lebgth by 1.
  v_lower := set_masklen(p_cidr, masklen(p_cidr) + 1);

-- If lower half was requested, done.
-- Else turn to 1 the bit that was added to the mask.
  if p_part = 0 then
    return v_lower;
  else
    return set_masklen((v_lower | hostmask(v_lower)) + 1, masklen(v_lower));
  end if;

end;
$$ language plpgsql;

create or replace function split_cidr6(p_cidr cidr, p_part integer) returns cidr as $$
-- IPv6 mask lengths are integer multiples of 4. This function increases mask length
-- of given cidr by 4, and returns one of the 16 possible cidrs that can be created
-- using this longer mask.
declare
  v_new cidr;
  v_part inet;
begin

-- Increase mask length by 4.
  v_new := set_masklen(p_cidr, masklen(p_cidr) + 4);

  if p_part = 0 then

-- Adding nothing is quite simple.
    return v_new;

  else

-- Nonzero value must be turned into an inet, because that's pretty much
-- the only type that we can combine to a cidr with a binary 'or'.
-- This code is awkward. If you know a more elegant and preferably faster
-- way that actually works, it would be warmly welcomed.
    v_part := substr(regexp_replace(rpad(lpad(to_hex(p_part), masklen(p_cidr) / 4 + 1,
              '0'), 32, '0'), '(....)', E':\\1', 'g'), 2)::inet;
    return set_masklen(v_new | v_part, masklen(v_new));

  end if;

end;
$$ language plpgsql;

create or replace function unallocated_subnets(p_server integer, p_cidr cidr) returns setof cidr as $$
-- Gets cidr as parameter; this should be a net. Treats ip addresses as a tree
-- structure, returning a list of cidrs which include all address ranges that
-- are not part of any subnet. IPv4 and IPv6.
declare
  v_count integer;
begin

-- If this cidr corresponds to a subnet, do nothing.
  select count(*) into v_count from nets
  where net = p_cidr and server = p_server and subnet = true and dummy = false;
  if v_count = 1 then return; end if;

-- If this cidr contains no subnets, return cidr and stop.
  select count(*) into v_count from nets
  where net << p_cidr and server = p_server and dummy = false;
  if v_count = 0 then return next p_cidr; return; end if;

-- Otherwise, IPv4 and IPv6 are handled differently.
  if family(p_cidr) = 4 then

-- An IPv4 cidr is split into lower and upper addresses,
-- and this same check is done separately for each.
    return query select unallocated_subnets(p_server, split_cidr4(p_cidr, 0));
    return query select unallocated_subnets(p_server, split_cidr4(p_cidr, 1));

  elsif family(p_cidr) = 6 then

-- For IPv6, mask length must be an integer multiple of 4.
-- No error is raised; that could cause problems that we don't need.
    if masklen(p_cidr) % 4 != 0 then return; end if;

-- For IPv6, the address range is split into 16 parts
-- and each is checked separately.
    for ind1 in 0..15 loop
      return query select unallocated_subnets(p_server, split_cidr6(p_cidr, ind1));
    end loop;

  end if;

end;
$$ language plpgsql;
