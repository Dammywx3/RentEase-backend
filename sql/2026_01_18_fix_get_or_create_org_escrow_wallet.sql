-- Fix: missing function required by purchase escrow release flow
-- Creates: public.get_or_create_org_escrow_wallet(uuid) -> uuid

CREATE OR REPLACE FUNCTION public.get_or_create_org_escrow_wallet(p_org_id uuid)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_wallet_id uuid;

  cand_sig text;
  cand_sigs text[] := ARRAY[
    'public.get_or_create_org_wallet(uuid,text)',
    'public.get_or_create_org_wallet_account(uuid,text)',
    'public.get_or_create_wallet(uuid,text)',
    'public.get_or_create_wallet_account(uuid,text)',
    'public.ensure_org_wallet(uuid,text)',
    'public.get_or_create_wallet_by_kind(uuid,text)',
    'public.get_or_create_escrow_wallet(uuid)',
    'public.get_or_create_org_escrow_account(uuid)'
  ];

  kind_col text;
  kind_udt_schema text;
  kind_udt_name text;

  has_org_id boolean;
  has_deleted_at boolean;

  required_cols text;
BEGIN
  --------------------------------------------------------------------
  -- 1) BEST CASE: you already have a helper function (different name)
  --------------------------------------------------------------------
  FOREACH cand_sig IN ARRAY cand_sigs LOOP
    IF to_regprocedure(cand_sig) IS NOT NULL THEN
      BEGIN
        -- 2-arg helpers: (uuid, text)
        IF cand_sig LIKE '%(uuid,text)%' THEN
          EXECUTE format('SELECT %s($1,$2)', split_part(cand_sig, '(', 1))
          USING p_org_id, 'escrow'
          INTO v_wallet_id;

          IF v_wallet_id IS NOT NULL THEN
            RETURN v_wallet_id;
          END IF;

        -- 1-arg helpers: (uuid)
        ELSIF cand_sig LIKE '%(uuid)%' THEN
          EXECUTE format('SELECT %s($1)', split_part(cand_sig, '(', 1))
          USING p_org_id
          INTO v_wallet_id;

          IF v_wallet_id IS NOT NULL THEN
            RETURN v_wallet_id;
          END IF;
        END IF;
      EXCEPTION WHEN others THEN
        -- Ignore and try next candidate
        NULL;
      END;
    END IF;
  END LOOP;

  --------------------------------------------------------------------
  -- 2) FALLBACK: attempt using wallet_accounts table if present
  --------------------------------------------------------------------
  IF to_regclass('public.wallet_accounts') IS NULL THEN
    RAISE EXCEPTION
      'Missing escrow wallet helper and public.wallet_accounts does not exist. Need a wallet_accounts table or a helper function.';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='wallet_accounts' AND column_name='organization_id'
  ) INTO has_org_id;

  IF NOT has_org_id THEN
    RAISE EXCEPTION
      'public.wallet_accounts exists but has no organization_id column. Cannot create org escrow wallet automatically.';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='wallet_accounts' AND column_name='deleted_at'
  ) INTO has_deleted_at;

  -- detect kind/type column name (most common patterns)
  SELECT c.column_name, c.udt_schema, c.udt_name
  INTO kind_col, kind_udt_schema, kind_udt_name
  FROM information_schema.columns c
  WHERE c.table_schema='public'
    AND c.table_name='wallet_accounts'
    AND c.column_name IN ('wallet_kind','wallet_type','kind','type','account_type')
  ORDER BY CASE c.column_name
    WHEN 'wallet_kind' THEN 1
    WHEN 'wallet_type' THEN 2
    WHEN 'account_type' THEN 3
    WHEN 'kind' THEN 4
    WHEN 'type' THEN 5
    ELSE 99 END
  LIMIT 1;

  IF kind_col IS NULL THEN
    RAISE EXCEPTION
      'public.wallet_accounts has no kind/type column (tried wallet_kind,wallet_type,kind,type,account_type). Cannot create escrow wallet automatically.';
  END IF;

  -- Try to find existing escrow wallet row
  EXECUTE format(
    'SELECT id FROM public.wallet_accounts WHERE organization_id=$1 %s AND %I::text IN (''escrow'',''org_escrow'',''purchase_escrow'') LIMIT 1',
    CASE WHEN has_deleted_at THEN 'AND deleted_at IS NULL' ELSE '' END,
    kind_col
  )
  USING p_org_id
  INTO v_wallet_id;

  IF v_wallet_id IS NOT NULL THEN
    RETURN v_wallet_id;
  END IF;

  --------------------------------------------------------------------
  -- 3) Safe insert attempt (only if table allows minimal insert)
  --    We only insert organization_id + kind_col, and rely on defaults
  --    If wallet_accounts has other required cols w/out defaults, we fail
  --------------------------------------------------------------------
  SELECT string_agg(c.column_name, ', ' ORDER BY c.ordinal_position)
  INTO required_cols
  FROM information_schema.columns c
  WHERE c.table_schema='public'
    AND c.table_name='wallet_accounts'
    AND c.is_nullable='NO'
    AND c.column_default IS NULL
    AND c.column_name NOT IN ('id'); -- assume id has default or is generated elsewhere

  -- If there are required cols besides organization_id/kind_col, we cannot safely insert
  IF required_cols IS NOT NULL THEN
    -- allow if required list is exactly organization_id + kind_col (order may vary)
    IF NOT (
      (required_cols = kind_col || ', organization_id') OR
      (required_cols = 'organization_id, ' || kind_col) OR
      (required_cols = 'organization_id') OR
      (required_cols = kind_col)
    ) THEN
      RAISE EXCEPTION
        'Cannot auto-create escrow wallet. wallet_accounts has required columns without defaults: %',
        required_cols;
    END IF;
  END IF;

  -- Insert with proper casting if kind column is an enum/domain
  BEGIN
    EXECUTE format(
      'INSERT INTO public.wallet_accounts (organization_id, %I) VALUES ($1, $2::%I.%I) RETURNING id',
      kind_col, kind_udt_schema, kind_udt_name
    )
    USING p_org_id, 'escrow'
    INTO v_wallet_id;
  EXCEPTION WHEN others THEN
    -- try plain text assignment (if kind col is text/varchar)
    EXECUTE format(
      'INSERT INTO public.wallet_accounts (organization_id, %I) VALUES ($1, $2) RETURNING id',
      kind_col
    )
    USING p_org_id, 'escrow'
    INTO v_wallet_id;
  END;

  RETURN v_wallet_id;
END;
$$;

-- Quick sanity check helper (optional):
-- SELECT public.get_or_create_org_escrow_wallet(current_organization_uuid());
