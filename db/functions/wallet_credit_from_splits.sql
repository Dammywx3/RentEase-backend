        CREATE OR REPLACE FUNCTION public.wallet_credit_from_splits(p_payment_id uuid)
         RETURNS void
         LANGUAGE plpgsql
1       AS $function$
2       DECLARE
3         v_org uuid;
4         v_ref_type text;
5         v_ref_id uuid;
6       
7         s record;
8         v_wallet uuid;
9         v_kind text;
10        v_user uuid;
11      
12        v_txn public.wallet_transaction_type;
13      BEGIN
14        -- Load payment reference info (do NOT assume payments.organization_id exists)
15        SELECT p.reference_type::text, p.reference_id
16        INTO v_ref_type, v_ref_id
17        FROM public.payments p
18        WHERE p.id = p_payment_id
19          AND p.deleted_at IS NULL;
20      
21        IF v_ref_type IS NULL THEN
22          RAISE EXCEPTION 'payment not found: %', p_payment_id;
23        END IF;
24      
25        -- 1) Try session org first (if your middleware sets it)
26        BEGIN
27          v_org := current_organization_uuid();
28        EXCEPTION WHEN OTHERS THEN
29          v_org := NULL;
30        END;
31      
32        -- 2) If session org missing, infer org from the payment reference
33        IF v_org IS NULL THEN
34          IF v_ref_type = 'purchase' THEN
35            SELECT organization_id INTO v_org
36            FROM public.property_purchases
37            WHERE id = v_ref_id
38              AND deleted_at IS NULL
39            LIMIT 1;
40          ELSIF v_ref_type = 'rent_invoice' THEN
41            SELECT organization_id INTO v_org
42            FROM public.rent_invoices
43            WHERE id = v_ref_id
44              AND deleted_at IS NULL
45            LIMIT 1;
46          END IF;
47        END IF;
48      
49        -- 3) Last fallback: infer from payment.property_id -> properties.organization_id (if available)
50        IF v_org IS NULL THEN
51          BEGIN
52            SELECT pr.organization_id INTO v_org
53            FROM public.payments p
54            JOIN public.properties pr ON pr.id = p.property_id
55            WHERE p.id = p_payment_id
56              AND p.deleted_at IS NULL
57              AND pr.deleted_at IS NULL
58            LIMIT 1;
59          EXCEPTION WHEN OTHERS THEN
60            v_org := NULL;
61          END;
62        END IF;
63      
64        IF v_org IS NULL THEN
65          RAISE EXCEPTION 'Cannot infer organization_id for payment %. Set app.organization_id or ensure reference tables have org.', p_payment_id;
66        END IF;
67      
68        -- Must have splits before we credit
69        IF NOT EXISTS (SELECT 1 FROM public.payment_splits ps WHERE ps.payment_id = p_payment_id) THEN
70          RAISE EXCEPTION 'No payment_splits for payment %. Run ensure_payment_splits() before crediting.', p_payment_id;
71        END IF;
72      
73        -- Write credits from each split
74        FOR s IN
75          SELECT
76            ps.split_type,
77            ps.beneficiary_kind,
78            ps.beneficiary_user_id,
79            ps.amount,
80            ps.currency
81          FROM public.payment_splits ps
82          WHERE ps.payment_id = p_payment_id
83          ORDER BY ps.created_at ASC
84        LOOP
85          v_kind := s.beneficiary_kind::text;
86          v_user := s.beneficiary_user_id;
87      
88          -- pick wallet using org + kind + user + currency
89          v_wallet := public.find_wallet_account_id(v_org, v_kind, v_user, s.currency::text);
90      
91          IF v_wallet IS NULL THEN
92            RAISE EXCEPTION
93              'No wallet_account found for org=% kind=% user=% currency=% (payment=% split_type=%)',
94              v_org, v_kind, v_user, s.currency, p_payment_id, s.split_type::text;
95          END IF;
96      
97          v_txn :=
98            CASE
99              WHEN s.split_type = 'payee'::public.split_type THEN 'credit_payee'::public.wallet_transaction_type
100             WHEN s.split_type = 'agent_markup'::public.split_type THEN 'credit_agent_markup'::public.wallet_transaction_type
101             WHEN s.split_type = 'agent_commission'::public.split_type THEN 'credit_agent_commission'::public.wallet_transaction_type
102             WHEN s.split_type = 'platform_fee'::public.split_type THEN 'credit_platform_fee'::public.wallet_transaction_type
103             ELSE 'adjustment'::public.wallet_transaction_type
104           END;
105     
106         INSERT INTO public.wallet_transactions(
107           organization_id,
108           wallet_account_id,
109           txn_type,
110           reference_type,
111           reference_id,
112           amount,
113           currency,
114           note
115         )
116         VALUES (
117           v_org,
118           v_wallet,
119           v_txn,
120           'payment',
121           p_payment_id,
122           s.amount,
123           s.currency,
124           'Credit from payment ' || p_payment_id::text || ' (' || s.split_type::text || ')'
125         )
126         ON CONFLICT DO NOTHING;
127       END LOOP;
128     
129     END;
130     $function$
