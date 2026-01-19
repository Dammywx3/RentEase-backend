--
-- PostgreSQL database dump
--

\restrict sLkTYSF8necqXf2210xohYx7ZUNmDI812jjU8tGxYfmGhgT5wNPHbWaZ104olgU

-- Dumped from database version 16.11 (Homebrew)
-- Dumped by pg_dump version 16.11 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: invoice_payments; Type: TABLE; Schema: public; Owner: mac
--

CREATE TABLE public.invoice_payments (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    invoice_id uuid NOT NULL,
    payment_id uuid NOT NULL,
    amount numeric(15,2) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid(),
    CONSTRAINT chk_invoice_payment_amount CHECK ((amount > (0)::numeric))
);

ALTER TABLE ONLY public.invoice_payments FORCE ROW LEVEL SECURITY;


ALTER TABLE public.invoice_payments OWNER TO mac;

--
-- Name: payments; Type: TABLE; Schema: public; Owner: rentease_service
--

CREATE TABLE public.payments (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    listing_id uuid NOT NULL,
    property_id uuid NOT NULL,
    amount numeric(15,2) NOT NULL,
    currency character varying(3),
    status public.payment_status DEFAULT 'pending'::public.payment_status,
    transaction_reference character varying(100) NOT NULL,
    payment_method public.payment_method NOT NULL,
    gateway_transaction_id character varying(100),
    gateway_response jsonb,
    platform_fee_amount numeric(15,2),
    agent_markup_amount numeric(15,2),
    agent_commission_amount numeric(15,2),
    payee_amount numeric(15,2),
    initiated_at timestamp with time zone DEFAULT now(),
    completed_at timestamp with time zone,
    receipt_number bigint,
    receipt_pdf_url text,
    receipt_generated boolean DEFAULT false,
    dispute_reason text,
    refunded_amount numeric(15,2),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    reference_type text,
    reference_id uuid,
    CONSTRAINT chk_completed_after_initiated CHECK (((completed_at IS NULL) OR (completed_at >= initiated_at))),
    CONSTRAINT chk_payment_amount_positive CHECK ((amount > (0)::numeric)),
    CONSTRAINT chk_refunded_amount CHECK (((refunded_amount IS NULL) OR (refunded_amount >= (0)::numeric)))
);

ALTER TABLE ONLY public.payments FORCE ROW LEVEL SECURITY;


ALTER TABLE public.payments OWNER TO rentease_service;

--
-- Name: rent_invoice_payments; Type: TABLE; Schema: public; Owner: mac
--

CREATE TABLE public.rent_invoice_payments (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid(),
    invoice_id uuid NOT NULL,
    rent_payment_id uuid NOT NULL,
    amount numeric(15,2) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT rent_invoice_payments_amount_check CHECK ((amount > (0)::numeric))
);


ALTER TABLE public.rent_invoice_payments OWNER TO mac;

--
-- Name: rent_invoices; Type: TABLE; Schema: public; Owner: mac
--

CREATE TABLE public.rent_invoices (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid() NOT NULL,
    tenancy_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    property_id uuid NOT NULL,
    invoice_number bigint DEFAULT nextval('public.rentease_invoice_seq'::regclass),
    status public.invoice_status DEFAULT 'issued'::public.invoice_status,
    period_start date NOT NULL,
    period_end date NOT NULL,
    due_date date NOT NULL,
    subtotal numeric(15,2) NOT NULL,
    late_fee_amount numeric(15,2) DEFAULT 0,
    total_amount numeric(15,2) NOT NULL,
    currency character varying(3) DEFAULT 'USD'::character varying,
    paid_amount numeric(15,2) DEFAULT 0,
    paid_at timestamp with time zone,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_invoice_amounts CHECK (((subtotal >= (0)::numeric) AND (late_fee_amount >= (0)::numeric) AND (total_amount >= (0)::numeric))),
    CONSTRAINT chk_invoice_period CHECK ((period_start <= period_end)),
    CONSTRAINT chk_paid_amount CHECK ((paid_amount >= (0)::numeric))
);

ALTER TABLE ONLY public.rent_invoices FORCE ROW LEVEL SECURITY;


ALTER TABLE public.rent_invoices OWNER TO mac;

--
-- Name: rent_payments; Type: TABLE; Schema: public; Owner: mac
--

CREATE TABLE public.rent_payments (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid() NOT NULL,
    invoice_id uuid NOT NULL,
    tenancy_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    property_id uuid NOT NULL,
    amount numeric(15,2) NOT NULL,
    currency character varying(3) DEFAULT 'USD'::character varying,
    payment_method text NOT NULL,
    status text DEFAULT 'successful'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT rent_payments_amount_check CHECK ((amount > (0)::numeric))
);


ALTER TABLE public.rent_payments OWNER TO mac;

--
-- Name: invoice_payments invoice_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: mac
--

ALTER TABLE ONLY public.invoice_payments
    ADD CONSTRAINT invoice_payments_pkey PRIMARY KEY (id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: rentease_service
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: rent_invoice_payments rent_invoice_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: mac
--

ALTER TABLE ONLY public.rent_invoice_payments
    ADD CONSTRAINT rent_invoice_payments_pkey PRIMARY KEY (id);


--
-- Name: rent_invoices rent_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: mac
--

ALTER TABLE ONLY public.rent_invoices
    ADD CONSTRAINT rent_invoices_pkey PRIMARY KEY (id);


--
-- Name: rent_payments rent_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: mac
--

ALTER TABLE ONLY public.rent_payments
    ADD CONSTRAINT rent_payments_pkey PRIMARY KEY (id);


--
-- Name: invoice_payments uniq_invoice_payment; Type: CONSTRAINT; Schema: public; Owner: mac
--

ALTER TABLE ONLY public.invoice_payments
    ADD CONSTRAINT uniq_invoice_payment UNIQUE (invoice_id, payment_id);


--
-- Name: payments uniq_transaction_reference; Type: CONSTRAINT; Schema: public; Owner: rentease_service
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT uniq_transaction_reference UNIQUE (transaction_reference);


--
-- Name: idx_invoice_payments_invoice; Type: INDEX; Schema: public; Owner: mac
--

CREATE INDEX idx_invoice_payments_invoice ON public.invoice_payments USING btree (invoice_id);


--
-- Name: idx_invoice_payments_org; Type: INDEX; Schema: public; Owner: mac
--

CREATE INDEX idx_invoice_payments_org ON public.invoice_payments USING btree (organization_id);


--
-- Name: idx_invoice_payments_payment; Type: INDEX; Schema: public; Owner: mac
--

CREATE INDEX idx_invoice_payments_payment ON public.invoice_payments USING btree (payment_id);


--
-- Name: idx_payments_gateway_response_gin; Type: INDEX; Schema: public; Owner: rentease_service
--

CREATE INDEX idx_payments_gateway_response_gin ON public.payments USING gin (gateway_response);


--
-- Name: idx_payments_listing_status; Type: INDEX; Schema: public; Owner: rentease_service
--

CREATE INDEX idx_payments_listing_status ON public.payments USING btree (listing_id, status);


--
-- Name: idx_payments_property_id; Type: INDEX; Schema: public; Owner: rentease_service
--

CREATE INDEX idx_payments_property_id ON public.payments USING btree (property_id);


--
-- Name: idx_payments_reference; Type: INDEX; Schema: public; Owner: rentease_service
--

CREATE INDEX idx_payments_reference ON public.payments USING btree (reference_type, reference_id);


--
-- Name: idx_payments_status_created_at; Type: INDEX; Schema: public; Owner: rentease_service
--

CREATE INDEX idx_payments_status_created_at ON public.payments USING btree (status, created_at);


--
-- Name: idx_payments_tenant_id; Type: INDEX; Schema: public; Owner: rentease_service
--

CREATE INDEX idx_payments_tenant_id ON public.payments USING btree (tenant_id);


--
-- Name: idx_rent_invoices_org_due; Type: INDEX; Schema: public; Owner: mac
--

CREATE INDEX idx_rent_invoices_org_due ON public.rent_invoices USING btree (organization_id, due_date, status);


--
-- Name: idx_rent_invoices_property; Type: INDEX; Schema: public; Owner: mac
--

CREATE INDEX idx_rent_invoices_property ON public.rent_invoices USING btree (property_id, due_date);


--
-- Name: idx_rent_invoices_tenancy; Type: INDEX; Schema: public; Owner: mac
--

CREATE INDEX idx_rent_invoices_tenancy ON public.rent_invoices USING btree (tenancy_id, due_date);


--
-- Name: idx_rent_invoices_tenant_due; Type: INDEX; Schema: public; Owner: mac
--

CREATE INDEX idx_rent_invoices_tenant_due ON public.rent_invoices USING btree (tenant_id, due_date, status);


--
-- Name: uniq_rent_invoice_org_number; Type: INDEX; Schema: public; Owner: mac
--

CREATE UNIQUE INDEX uniq_rent_invoice_org_number ON public.rent_invoices USING btree (organization_id, invoice_number) WHERE (deleted_at IS NULL);


--
-- Name: uniq_rent_invoice_payments_invoice; Type: INDEX; Schema: public; Owner: mac
--

CREATE UNIQUE INDEX uniq_rent_invoice_payments_invoice ON public.rent_invoice_payments USING btree (invoice_id);


--
-- Name: uniq_rent_payments_invoice; Type: INDEX; Schema: public; Owner: mac
--

CREATE UNIQUE INDEX uniq_rent_payments_invoice ON public.rent_payments USING btree (invoice_id);


--
-- Name: invoice_payments audit_invoice_payments; Type: TRIGGER; Schema: public; Owner: mac
--

CREATE TRIGGER audit_invoice_payments AFTER INSERT OR DELETE OR UPDATE ON public.invoice_payments FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: payments audit_payments; Type: TRIGGER; Schema: public; Owner: rentease_service
--

CREATE TRIGGER audit_payments AFTER INSERT OR DELETE OR UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: rent_invoices audit_rent_invoices; Type: TRIGGER; Schema: public; Owner: mac
--

CREATE TRIGGER audit_rent_invoices AFTER INSERT OR DELETE OR UPDATE ON public.rent_invoices FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: payments set_updated_at_payments; Type: TRIGGER; Schema: public; Owner: rentease_service
--

CREATE TRIGGER set_updated_at_payments BEFORE UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: rent_invoices set_updated_at_rent_invoices; Type: TRIGGER; Schema: public; Owner: mac
--

CREATE TRIGGER set_updated_at_rent_invoices BEFORE UPDATE ON public.rent_invoices FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: payments trg_validate_payment_matches_listing; Type: TRIGGER; Schema: public; Owner: rentease_service
--

CREATE TRIGGER trg_validate_payment_matches_listing BEFORE INSERT OR UPDATE OF listing_id, property_id, amount, currency ON public.payments FOR EACH ROW EXECUTE FUNCTION public.validate_payment_matches_listing();


--
-- Name: payments trigger_payments_success; Type: TRIGGER; Schema: public; Owner: rentease_service
--

CREATE TRIGGER trigger_payments_success AFTER UPDATE OF status ON public.payments FOR EACH ROW WHEN ((new.status = 'successful'::public.payment_status)) EXECUTE FUNCTION public.payments_success_trigger_fn();


--
-- Name: invoice_payments invoice_payments_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mac
--

ALTER TABLE ONLY public.invoice_payments
    ADD CONSTRAINT invoice_payments_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.rent_invoices(id) ON DELETE CASCADE;


--
-- Name: invoice_payments invoice_payments_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mac
--

ALTER TABLE ONLY public.invoice_payments
    ADD CONSTRAINT invoice_payments_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.payments(id) ON DELETE RESTRICT;


--
-- Name: payments payments_listing_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rentease_service
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_listing_id_fkey FOREIGN KEY (listing_id) REFERENCES public.property_listings(id) ON DELETE RESTRICT;


--
-- Name: payments payments_property_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rentease_service
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE RESTRICT;


--
-- Name: payments payments_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rentease_service
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.users(id);


--
-- Name: rent_invoice_payments rent_invoice_payments_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mac
--

ALTER TABLE ONLY public.rent_invoice_payments
    ADD CONSTRAINT rent_invoice_payments_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.rent_invoices(id) ON DELETE CASCADE;


--
-- Name: rent_invoice_payments rent_invoice_payments_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mac
--

ALTER TABLE ONLY public.rent_invoice_payments
    ADD CONSTRAINT rent_invoice_payments_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: rent_invoice_payments rent_invoice_payments_rent_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mac
--

ALTER TABLE ONLY public.rent_invoice_payments
    ADD CONSTRAINT rent_invoice_payments_rent_payment_id_fkey FOREIGN KEY (rent_payment_id) REFERENCES public.rent_payments(id) ON DELETE RESTRICT;


--
-- Name: rent_invoices rent_invoices_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mac
--

ALTER TABLE ONLY public.rent_invoices
    ADD CONSTRAINT rent_invoices_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: rent_invoices rent_invoices_property_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mac
--

ALTER TABLE ONLY public.rent_invoices
    ADD CONSTRAINT rent_invoices_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE RESTRICT;


--
-- Name: rent_invoices rent_invoices_tenancy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mac
--

ALTER TABLE ONLY public.rent_invoices
    ADD CONSTRAINT rent_invoices_tenancy_id_fkey FOREIGN KEY (tenancy_id) REFERENCES public.tenancies(id) ON DELETE CASCADE;


--
-- Name: rent_invoices rent_invoices_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mac
--

ALTER TABLE ONLY public.rent_invoices
    ADD CONSTRAINT rent_invoices_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: rent_payments rent_payments_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mac
--

ALTER TABLE ONLY public.rent_payments
    ADD CONSTRAINT rent_payments_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.rent_invoices(id) ON DELETE CASCADE;


--
-- Name: rent_payments rent_payments_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mac
--

ALTER TABLE ONLY public.rent_payments
    ADD CONSTRAINT rent_payments_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: rent_payments rent_payments_property_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mac
--

ALTER TABLE ONLY public.rent_payments
    ADD CONSTRAINT rent_payments_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE RESTRICT;


--
-- Name: rent_payments rent_payments_tenancy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mac
--

ALTER TABLE ONLY public.rent_payments
    ADD CONSTRAINT rent_payments_tenancy_id_fkey FOREIGN KEY (tenancy_id) REFERENCES public.tenancies(id) ON DELETE RESTRICT;


--
-- Name: rent_payments rent_payments_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mac
--

ALTER TABLE ONLY public.rent_payments
    ADD CONSTRAINT rent_payments_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: invoice_payments; Type: ROW SECURITY; Schema: public; Owner: mac
--

ALTER TABLE public.invoice_payments ENABLE ROW LEVEL SECURITY;

--
-- Name: invoice_payments invoice_payments_select; Type: POLICY; Schema: public; Owner: mac
--

CREATE POLICY invoice_payments_select ON public.invoice_payments FOR SELECT USING (((organization_id = public.current_organization_uuid()) AND (EXISTS ( SELECT 1
   FROM public.rent_invoices ri
  WHERE ((ri.id = invoice_payments.invoice_id) AND (ri.deleted_at IS NULL) AND (ri.organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (ri.tenant_id = public.current_user_uuid()) OR public.is_property_owner_or_default_agent(ri.property_id)))))));


--
-- Name: invoice_payments invoice_payments_write_delete; Type: POLICY; Schema: public; Owner: mac
--

CREATE POLICY invoice_payments_write_delete ON public.invoice_payments FOR DELETE USING ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name)));


--
-- Name: invoice_payments invoice_payments_write_insert; Type: POLICY; Schema: public; Owner: mac
--

CREATE POLICY invoice_payments_write_insert ON public.invoice_payments FOR INSERT WITH CHECK (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (CURRENT_USER = 'rentease_service'::name) OR (EXISTS ( SELECT 1
   FROM (public.rent_invoices ri
     JOIN public.payments p ON ((p.id = invoice_payments.payment_id)))
  WHERE ((ri.id = invoice_payments.invoice_id) AND (ri.deleted_at IS NULL) AND (ri.organization_id = public.current_organization_uuid()) AND (ri.tenant_id = public.current_user_uuid()) AND (p.deleted_at IS NULL) AND (p.tenant_id = public.current_user_uuid())))))));


--
-- Name: invoice_payments invoice_payments_write_update; Type: POLICY; Schema: public; Owner: mac
--

CREATE POLICY invoice_payments_write_update ON public.invoice_payments FOR UPDATE USING ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name))) WITH CHECK (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (CURRENT_USER = 'rentease_service'::name))));


--
-- Name: payments; Type: ROW SECURITY; Schema: public; Owner: rentease_service
--

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

--
-- Name: payments payments_delete_policy; Type: POLICY; Schema: public; Owner: rentease_service
--

CREATE POLICY payments_delete_policy ON public.payments FOR DELETE USING (((deleted_at IS NULL) AND ((tenant_id = public.current_user_uuid()) OR public.is_admin())));


--
-- Name: payments payments_insert_policy; Type: POLICY; Schema: public; Owner: rentease_service
--

CREATE POLICY payments_insert_policy ON public.payments FOR INSERT WITH CHECK (((tenant_id = public.current_user_uuid()) OR public.is_admin()));


--
-- Name: payments payments_select_policy; Type: POLICY; Schema: public; Owner: rentease_service
--

CREATE POLICY payments_select_policy ON public.payments FOR SELECT USING (((deleted_at IS NULL) AND ((tenant_id = public.current_user_uuid()) OR public.is_listing_participant(listing_id) OR public.is_admin())));


--
-- Name: payments payments_service_update; Type: POLICY; Schema: public; Owner: rentease_service
--

CREATE POLICY payments_service_update ON public.payments FOR UPDATE USING ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name))) WITH CHECK ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name)));


--
-- Name: payments payments_update_policy; Type: POLICY; Schema: public; Owner: rentease_service
--

CREATE POLICY payments_update_policy ON public.payments FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: rent_invoice_payments; Type: ROW SECURITY; Schema: public; Owner: mac
--

ALTER TABLE public.rent_invoice_payments ENABLE ROW LEVEL SECURITY;

--
-- Name: rent_invoice_payments rent_invoice_payments_select; Type: POLICY; Schema: public; Owner: mac
--

CREATE POLICY rent_invoice_payments_select ON public.rent_invoice_payments FOR SELECT USING (((organization_id = public.current_organization_uuid()) AND (EXISTS ( SELECT 1
   FROM public.rent_invoices ri
  WHERE ((ri.id = rent_invoice_payments.invoice_id) AND (ri.deleted_at IS NULL) AND (ri.organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (ri.tenant_id = public.current_user_uuid()) OR public.is_property_owner_or_default_agent(ri.property_id)))))));


--
-- Name: rent_invoice_payments rent_invoice_payments_write_admin_or_service; Type: POLICY; Schema: public; Owner: mac
--

CREATE POLICY rent_invoice_payments_write_admin_or_service ON public.rent_invoice_payments USING ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name))) WITH CHECK (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (CURRENT_USER = 'rentease_service'::name))));


--
-- Name: rent_invoices; Type: ROW SECURITY; Schema: public; Owner: mac
--

ALTER TABLE public.rent_invoices ENABLE ROW LEVEL SECURITY;

--
-- Name: rent_invoices rent_invoices_delete; Type: POLICY; Schema: public; Owner: mac
--

CREATE POLICY rent_invoices_delete ON public.rent_invoices FOR DELETE USING ((public.is_admin() AND (organization_id = public.current_organization_uuid())));


--
-- Name: rent_invoices rent_invoices_insert; Type: POLICY; Schema: public; Owner: mac
--

CREATE POLICY rent_invoices_insert ON public.rent_invoices FOR INSERT WITH CHECK (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR public.is_property_owner_or_default_agent(property_id))));


--
-- Name: rent_invoices rent_invoices_select; Type: POLICY; Schema: public; Owner: mac
--

CREATE POLICY rent_invoices_select ON public.rent_invoices FOR SELECT USING (((deleted_at IS NULL) AND (organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (tenant_id = public.current_user_uuid()) OR public.is_property_owner_or_default_agent(property_id))));


--
-- Name: rent_invoices rent_invoices_update; Type: POLICY; Schema: public; Owner: mac
--

CREATE POLICY rent_invoices_update ON public.rent_invoices FOR UPDATE USING (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR public.is_property_owner_or_default_agent(property_id)))) WITH CHECK (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR public.is_property_owner_or_default_agent(property_id))));


--
-- Name: rent_payments; Type: ROW SECURITY; Schema: public; Owner: mac
--

ALTER TABLE public.rent_payments ENABLE ROW LEVEL SECURITY;

--
-- Name: rent_payments rent_payments_select; Type: POLICY; Schema: public; Owner: mac
--

CREATE POLICY rent_payments_select ON public.rent_payments FOR SELECT USING (((organization_id = public.current_organization_uuid()) AND (EXISTS ( SELECT 1
   FROM public.rent_invoices ri
  WHERE ((ri.id = rent_payments.invoice_id) AND (ri.deleted_at IS NULL) AND (ri.organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (ri.tenant_id = public.current_user_uuid()) OR public.is_property_owner_or_default_agent(ri.property_id)))))));


--
-- Name: rent_payments rent_payments_write_admin_or_service; Type: POLICY; Schema: public; Owner: mac
--

CREATE POLICY rent_payments_write_admin_or_service ON public.rent_payments USING ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name))) WITH CHECK (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (CURRENT_USER = 'rentease_service'::name))));


--
-- Name: TABLE invoice_payments; Type: ACL; Schema: public; Owner: mac
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.invoice_payments TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.invoice_payments TO rentease_service;


--
-- Name: TABLE payments; Type: ACL; Schema: public; Owner: rentease_service
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.payments TO rentease_app;


--
-- Name: TABLE rent_invoice_payments; Type: ACL; Schema: public; Owner: mac
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.rent_invoice_payments TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.rent_invoice_payments TO rentease_service;


--
-- Name: TABLE rent_invoices; Type: ACL; Schema: public; Owner: mac
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.rent_invoices TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.rent_invoices TO rentease_service;


--
-- Name: TABLE rent_payments; Type: ACL; Schema: public; Owner: mac
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.rent_payments TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.rent_payments TO rentease_service;


--
-- PostgreSQL database dump complete
--

\unrestrict sLkTYSF8necqXf2210xohYx7ZUNmDI812jjU8tGxYfmGhgT5wNPHbWaZ104olgU

