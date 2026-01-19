--
-- PostgreSQL database dump
--

\restrict cGnz1NP39pN0yIcDGeu1f49EoSMNrAHeuGZmkxhL1GXgKIHDPfCtzbey4rF1n10

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

DROP POLICY IF EXISTS wallet_tx_update_admin_or_service ON public.wallet_transactions;
DROP POLICY IF EXISTS wallet_tx_select ON public.wallet_transactions;
DROP POLICY IF EXISTS wallet_tx_modify_admin_update ON public.wallet_transactions;
DROP POLICY IF EXISTS wallet_tx_modify_admin_insert ON public.wallet_transactions;
DROP POLICY IF EXISTS wallet_tx_modify_admin_delete ON public.wallet_transactions;
DROP POLICY IF EXISTS wallet_tx_insert_admin_or_service ON public.wallet_transactions;
DROP POLICY IF EXISTS wallet_tx_delete_admin_or_service ON public.wallet_transactions;
DROP POLICY IF EXISTS wallet_accounts_update_admin_or_service ON public.wallet_accounts;
DROP POLICY IF EXISTS wallet_accounts_update ON public.wallet_accounts;
DROP POLICY IF EXISTS wallet_accounts_select ON public.wallet_accounts;
DROP POLICY IF EXISTS wallet_accounts_insert_admin_or_service ON public.wallet_accounts;
DROP POLICY IF EXISTS wallet_accounts_insert ON public.wallet_accounts;
DROP POLICY IF EXISTS wallet_accounts_delete_admin_or_service ON public.wallet_accounts;
DROP POLICY IF EXISTS wallet_accounts_delete ON public.wallet_accounts;
DROP POLICY IF EXISTS tenancies_update_policy ON public.tenancies;
DROP POLICY IF EXISTS tenancies_select_policy ON public.tenancies;
DROP POLICY IF EXISTS tenancies_insert_policy ON public.tenancies;
DROP POLICY IF EXISTS tenancies_delete_policy ON public.tenancies;
DROP POLICY IF EXISTS support_tickets_update_policy ON public.support_tickets;
DROP POLICY IF EXISTS support_tickets_select_policy ON public.support_tickets;
DROP POLICY IF EXISTS support_tickets_insert_policy ON public.support_tickets;
DROP POLICY IF EXISTS support_tickets_delete_policy ON public.support_tickets;
DROP POLICY IF EXISTS sms_templates_all ON public.sms_templates;
DROP POLICY IF EXISTS saved_listings_update ON public.saved_listings;
DROP POLICY IF EXISTS saved_listings_select ON public.saved_listings;
DROP POLICY IF EXISTS saved_listings_insert ON public.saved_listings;
DROP POLICY IF EXISTS saved_listings_delete ON public.saved_listings;
DROP POLICY IF EXISTS sale_disclosures_update ON public.property_sale_disclosures;
DROP POLICY IF EXISTS sale_disclosures_select ON public.property_sale_disclosures;
DROP POLICY IF EXISTS sale_disclosures_insert ON public.property_sale_disclosures;
DROP POLICY IF EXISTS sale_disclosures_delete ON public.property_sale_disclosures;
DROP POLICY IF EXISTS rental_applications_update_policy ON public.rental_applications;
DROP POLICY IF EXISTS rental_applications_select_policy ON public.rental_applications;
DROP POLICY IF EXISTS rental_applications_insert_policy ON public.rental_applications;
DROP POLICY IF EXISTS rental_applications_delete_policy ON public.rental_applications;
DROP POLICY IF EXISTS rent_invoices_update ON public.rent_invoices;
DROP POLICY IF EXISTS rent_invoices_select ON public.rent_invoices;
DROP POLICY IF EXISTS rent_invoices_insert ON public.rent_invoices;
DROP POLICY IF EXISTS rent_invoices_delete ON public.rent_invoices;
DROP POLICY IF EXISTS property_viewings_update_policy ON public.property_viewings;
DROP POLICY IF EXISTS property_viewings_select_policy ON public.property_viewings;
DROP POLICY IF EXISTS property_viewings_insert_policy ON public.property_viewings;
DROP POLICY IF EXISTS property_viewings_delete_policy ON public.property_viewings;
DROP POLICY IF EXISTS property_sale_details_update ON public.property_sale_details;
DROP POLICY IF EXISTS property_sale_details_select ON public.property_sale_details;
DROP POLICY IF EXISTS property_sale_details_insert ON public.property_sale_details;
DROP POLICY IF EXISTS property_sale_details_delete ON public.property_sale_details;
DROP POLICY IF EXISTS property_media_update ON public.property_media;
DROP POLICY IF EXISTS property_media_select ON public.property_media;
DROP POLICY IF EXISTS property_media_insert ON public.property_media;
DROP POLICY IF EXISTS property_media_delete ON public.property_media;
DROP POLICY IF EXISTS properties_org_update ON public.properties;
DROP POLICY IF EXISTS properties_org_select ON public.properties;
DROP POLICY IF EXISTS properties_org_insert ON public.properties;
DROP POLICY IF EXISTS properties_org_delete ON public.properties;
DROP POLICY IF EXISTS properties_marketplace_select ON public.properties;
DROP POLICY IF EXISTS platform_settings_all ON public.platform_settings;
DROP POLICY IF EXISTS payouts_update_admin ON public.payouts;
DROP POLICY IF EXISTS payouts_insert ON public.payouts;
DROP POLICY IF EXISTS payout_accounts_update ON public.payout_accounts;
DROP POLICY IF EXISTS payout_accounts_select ON public.payout_accounts;
DROP POLICY IF EXISTS payout_accounts_insert ON public.payout_accounts;
DROP POLICY IF EXISTS payout_accounts_delete ON public.payout_accounts;
DROP POLICY IF EXISTS payments_update_policy ON public.payments;
DROP POLICY IF EXISTS payments_service_update ON public.payments;
DROP POLICY IF EXISTS payments_select_policy ON public.payments;
DROP POLICY IF EXISTS payments_insert_policy ON public.payments;
DROP POLICY IF EXISTS payments_delete_policy ON public.payments;
DROP POLICY IF EXISTS payment_splits_write_update ON public.payment_splits;
DROP POLICY IF EXISTS payment_splits_write_insert ON public.payment_splits;
DROP POLICY IF EXISTS payment_splits_write_delete ON public.payment_splits;
DROP POLICY IF EXISTS payment_splits_update ON public.payment_splits;
DROP POLICY IF EXISTS payment_splits_select ON public.payment_splits;
DROP POLICY IF EXISTS payment_splits_insert ON public.payment_splits;
DROP POLICY IF EXISTS payment_splits_delete ON public.payment_splits;
DROP POLICY IF EXISTS notifications_update_policy ON public.notifications;
DROP POLICY IF EXISTS notifications_select_policy ON public.notifications;
DROP POLICY IF EXISTS notifications_insert_policy ON public.notifications;
DROP POLICY IF EXISTS notifications_delete_policy ON public.notifications;
DROP POLICY IF EXISTS msg_attach_select ON public.message_attachments;
DROP POLICY IF EXISTS msg_attach_insert ON public.message_attachments;
DROP POLICY IF EXISTS msg_attach_delete ON public.message_attachments;
DROP POLICY IF EXISTS messages_update ON public.messages;
DROP POLICY IF EXISTS messages_select ON public.messages;
DROP POLICY IF EXISTS messages_insert ON public.messages;
DROP POLICY IF EXISTS messages_delete ON public.messages;
DROP POLICY IF EXISTS maint_updates_select ON public.maintenance_updates;
DROP POLICY IF EXISTS maint_updates_insert ON public.maintenance_updates;
DROP POLICY IF EXISTS maint_update ON public.maintenance_requests;
DROP POLICY IF EXISTS maint_select ON public.maintenance_requests;
DROP POLICY IF EXISTS maint_insert ON public.maintenance_requests;
DROP POLICY IF EXISTS maint_delete ON public.maintenance_requests;
DROP POLICY IF EXISTS maint_attach_select ON public.maintenance_attachments;
DROP POLICY IF EXISTS maint_attach_insert ON public.maintenance_attachments;
DROP POLICY IF EXISTS listings_update ON public.property_listings;
DROP POLICY IF EXISTS listings_public_select ON public.property_listings;
DROP POLICY IF EXISTS listings_insert ON public.property_listings;
DROP POLICY IF EXISTS listings_delete ON public.property_listings;
DROP POLICY IF EXISTS leads_policy ON public.leads;
DROP POLICY IF EXISTS lead_activities_policy ON public.lead_activities;
DROP POLICY IF EXISTS invoice_payments_write_update ON public.invoice_payments;
DROP POLICY IF EXISTS invoice_payments_write_insert ON public.invoice_payments;
DROP POLICY IF EXISTS invoice_payments_write_delete ON public.invoice_payments;
DROP POLICY IF EXISTS invoice_payments_select ON public.invoice_payments;
DROP POLICY IF EXISTS email_templates_all ON public.email_templates;
DROP POLICY IF EXISTS documents_update_policy ON public.documents;
DROP POLICY IF EXISTS documents_select_policy ON public.documents;
DROP POLICY IF EXISTS documents_insert_policy ON public.documents;
DROP POLICY IF EXISTS documents_delete_policy ON public.documents;
DROP POLICY IF EXISTS disputes_update_admin ON public.disputes;
DROP POLICY IF EXISTS disputes_select ON public.disputes;
DROP POLICY IF EXISTS disputes_insert ON public.disputes;
DROP POLICY IF EXISTS dispute_messages_select ON public.dispute_messages;
DROP POLICY IF EXISTS dispute_messages_insert ON public.dispute_messages;
DROP POLICY IF EXISTS cust_pm_write_update ON public.customer_payment_methods;
DROP POLICY IF EXISTS cust_pm_write_insert ON public.customer_payment_methods;
DROP POLICY IF EXISTS cust_pm_write_delete ON public.customer_payment_methods;
DROP POLICY IF EXISTS cust_pm_select ON public.customer_payment_methods;
DROP POLICY IF EXISTS conversations_update ON public.conversations;
DROP POLICY IF EXISTS conversations_select ON public.conversations;
DROP POLICY IF EXISTS conversations_insert ON public.conversations;
DROP POLICY IF EXISTS conversations_delete ON public.conversations;
DROP POLICY IF EXISTS conv_part_update ON public.conversation_participants;
DROP POLICY IF EXISTS conv_part_select ON public.conversation_participants;
DROP POLICY IF EXISTS conv_part_insert ON public.conversation_participants;
DROP POLICY IF EXISTS conv_part_delete ON public.conversation_participants;
DROP POLICY IF EXISTS contracts_update ON public.contracts;
DROP POLICY IF EXISTS contracts_select ON public.contracts;
DROP POLICY IF EXISTS contracts_insert ON public.contracts;
DROP POLICY IF EXISTS contracts_delete ON public.contracts;
DROP POLICY IF EXISTS contractors_write_update ON public.contractors;
DROP POLICY IF EXISTS contractors_write_insert ON public.contractors;
DROP POLICY IF EXISTS contractors_write_delete ON public.contractors;
DROP POLICY IF EXISTS contractors_select ON public.contractors;
DROP POLICY IF EXISTS contract_signatures_select ON public.contract_signatures;
DROP POLICY IF EXISTS contract_signatures_insert ON public.contract_signatures;
DROP POLICY IF EXISTS contract_parties_write_update ON public.contract_parties;
DROP POLICY IF EXISTS contract_parties_write_insert ON public.contract_parties;
DROP POLICY IF EXISTS contract_parties_write_delete ON public.contract_parties;
DROP POLICY IF EXISTS contract_parties_select ON public.contract_parties;
DROP POLICY IF EXISTS api_keys_all ON public.api_keys;
ALTER TABLE IF EXISTS ONLY public.wallet_transactions DROP CONSTRAINT IF EXISTS wallet_transactions_wallet_account_id_fkey;
ALTER TABLE IF EXISTS ONLY public.wallet_transactions DROP CONSTRAINT IF EXISTS wallet_transactions_organization_id_fkey;
ALTER TABLE IF EXISTS ONLY public.wallet_accounts DROP CONSTRAINT IF EXISTS wallet_accounts_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.wallet_accounts DROP CONSTRAINT IF EXISTS wallet_accounts_organization_id_fkey;
ALTER TABLE IF EXISTS ONLY public.users DROP CONSTRAINT IF EXISTS users_updated_by_fkey;
ALTER TABLE IF EXISTS ONLY public.users DROP CONSTRAINT IF EXISTS users_organization_id_fkey;
ALTER TABLE IF EXISTS ONLY public.users DROP CONSTRAINT IF EXISTS users_created_by_fkey;
ALTER TABLE IF EXISTS ONLY public.tenancies DROP CONSTRAINT IF EXISTS tenancies_tenant_id_fkey;
ALTER TABLE IF EXISTS ONLY public.tenancies DROP CONSTRAINT IF EXISTS tenancies_property_id_fkey;
ALTER TABLE IF EXISTS ONLY public.tenancies DROP CONSTRAINT IF EXISTS tenancies_listing_id_fkey;
ALTER TABLE IF EXISTS ONLY public.support_tickets DROP CONSTRAINT IF EXISTS support_tickets_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.support_tickets DROP CONSTRAINT IF EXISTS support_tickets_assigned_to_fkey;
ALTER TABLE IF EXISTS ONLY public.saved_listings DROP CONSTRAINT IF EXISTS saved_listings_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.saved_listings DROP CONSTRAINT IF EXISTS saved_listings_organization_id_fkey;
ALTER TABLE IF EXISTS ONLY public.saved_listings DROP CONSTRAINT IF EXISTS saved_listings_listing_id_fkey;
ALTER TABLE IF EXISTS ONLY public.rental_applications DROP CONSTRAINT IF EXISTS rental_applications_property_id_fkey;
ALTER TABLE IF EXISTS ONLY public.rental_applications DROP CONSTRAINT IF EXISTS rental_applications_listing_id_fkey;
ALTER TABLE IF EXISTS ONLY public.rental_applications DROP CONSTRAINT IF EXISTS rental_applications_applicant_id_fkey;
ALTER TABLE IF EXISTS ONLY public.rent_invoices DROP CONSTRAINT IF EXISTS rent_invoices_tenant_id_fkey;
ALTER TABLE IF EXISTS ONLY public.rent_invoices DROP CONSTRAINT IF EXISTS rent_invoices_tenancy_id_fkey;
ALTER TABLE IF EXISTS ONLY public.rent_invoices DROP CONSTRAINT IF EXISTS rent_invoices_property_id_fkey;
ALTER TABLE IF EXISTS ONLY public.rent_invoices DROP CONSTRAINT IF EXISTS rent_invoices_organization_id_fkey;
ALTER TABLE IF EXISTS ONLY public.property_viewings DROP CONSTRAINT IF EXISTS property_viewings_tenant_id_fkey;
ALTER TABLE IF EXISTS ONLY public.property_viewings DROP CONSTRAINT IF EXISTS property_viewings_property_id_fkey;
ALTER TABLE IF EXISTS ONLY public.property_viewings DROP CONSTRAINT IF EXISTS property_viewings_listing_id_fkey;
ALTER TABLE IF EXISTS ONLY public.property_sale_disclosures DROP CONSTRAINT IF EXISTS property_sale_disclosures_property_id_fkey;
ALTER TABLE IF EXISTS ONLY public.property_sale_disclosures DROP CONSTRAINT IF EXISTS property_sale_disclosures_document_id_fkey;
ALTER TABLE IF EXISTS ONLY public.property_sale_details DROP CONSTRAINT IF EXISTS property_sale_details_property_id_fkey;
ALTER TABLE IF EXISTS ONLY public.property_media DROP CONSTRAINT IF EXISTS property_media_property_id_fkey;
ALTER TABLE IF EXISTS ONLY public.property_media DROP CONSTRAINT IF EXISTS property_media_organization_id_fkey;
ALTER TABLE IF EXISTS ONLY public.property_listings DROP CONSTRAINT IF EXISTS property_listings_property_id_fkey;
ALTER TABLE IF EXISTS ONLY public.property_listings DROP CONSTRAINT IF EXISTS property_listings_payee_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.property_listings DROP CONSTRAINT IF EXISTS property_listings_owner_approved_by_fkey;
ALTER TABLE IF EXISTS ONLY public.property_listings DROP CONSTRAINT IF EXISTS property_listings_organization_id_fkey;
ALTER TABLE IF EXISTS ONLY public.property_listings DROP CONSTRAINT IF EXISTS property_listings_created_by_fkey;
ALTER TABLE IF EXISTS ONLY public.property_listings DROP CONSTRAINT IF EXISTS property_listings_agent_id_fkey;
ALTER TABLE IF EXISTS ONLY public.properties DROP CONSTRAINT IF EXISTS properties_updated_by_fkey;
ALTER TABLE IF EXISTS ONLY public.properties DROP CONSTRAINT IF EXISTS properties_owner_id_fkey;
ALTER TABLE IF EXISTS ONLY public.properties DROP CONSTRAINT IF EXISTS properties_organization_id_fkey;
ALTER TABLE IF EXISTS ONLY public.properties DROP CONSTRAINT IF EXISTS properties_default_agent_id_fkey;
ALTER TABLE IF EXISTS ONLY public.properties DROP CONSTRAINT IF EXISTS properties_created_by_fkey;
ALTER TABLE IF EXISTS ONLY public.payouts DROP CONSTRAINT IF EXISTS payouts_wallet_account_id_fkey;
ALTER TABLE IF EXISTS ONLY public.payouts DROP CONSTRAINT IF EXISTS payouts_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.payouts DROP CONSTRAINT IF EXISTS payouts_payout_account_id_fkey;
ALTER TABLE IF EXISTS ONLY public.payouts DROP CONSTRAINT IF EXISTS payouts_organization_id_fkey;
ALTER TABLE IF EXISTS ONLY public.payout_accounts DROP CONSTRAINT IF EXISTS payout_accounts_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.payout_accounts DROP CONSTRAINT IF EXISTS payout_accounts_organization_id_fkey;
ALTER TABLE IF EXISTS ONLY public.payments DROP CONSTRAINT IF EXISTS payments_tenant_id_fkey;
ALTER TABLE IF EXISTS ONLY public.payments DROP CONSTRAINT IF EXISTS payments_property_id_fkey;
ALTER TABLE IF EXISTS ONLY public.payments DROP CONSTRAINT IF EXISTS payments_listing_id_fkey;
ALTER TABLE IF EXISTS ONLY public.payment_splits DROP CONSTRAINT IF EXISTS payment_splits_payment_id_fkey;
ALTER TABLE IF EXISTS ONLY public.payment_splits DROP CONSTRAINT IF EXISTS payment_splits_beneficiary_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.notifications DROP CONSTRAINT IF EXISTS notifications_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.messages DROP CONSTRAINT IF EXISTS messages_sender_id_fkey;
ALTER TABLE IF EXISTS ONLY public.messages DROP CONSTRAINT IF EXISTS messages_organization_id_fkey;
ALTER TABLE IF EXISTS ONLY public.messages DROP CONSTRAINT IF EXISTS messages_conversation_id_fkey;
ALTER TABLE IF EXISTS ONLY public.message_attachments DROP CONSTRAINT IF EXISTS message_attachments_message_id_fkey;
ALTER TABLE IF EXISTS ONLY public.maintenance_updates DROP CONSTRAINT IF EXISTS maintenance_updates_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.maintenance_updates DROP CONSTRAINT IF EXISTS maintenance_updates_maintenance_request_id_fkey;
ALTER TABLE IF EXISTS ONLY public.maintenance_requests DROP CONSTRAINT IF EXISTS maintenance_requests_tenancy_id_fkey;
ALTER TABLE IF EXISTS ONLY public.maintenance_requests DROP CONSTRAINT IF EXISTS maintenance_requests_property_id_fkey;
ALTER TABLE IF EXISTS ONLY public.maintenance_requests DROP CONSTRAINT IF EXISTS maintenance_requests_organization_id_fkey;
ALTER TABLE IF EXISTS ONLY public.maintenance_requests DROP CONSTRAINT IF EXISTS maintenance_requests_created_by_fkey;
ALTER TABLE IF EXISTS ONLY public.maintenance_requests DROP CONSTRAINT IF EXISTS maintenance_requests_assigned_to_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.maintenance_requests DROP CONSTRAINT IF EXISTS maintenance_requests_assigned_contractor_id_fkey;
ALTER TABLE IF EXISTS ONLY public.maintenance_attachments DROP CONSTRAINT IF EXISTS maintenance_attachments_maintenance_request_id_fkey;
ALTER TABLE IF EXISTS ONLY public.leads DROP CONSTRAINT IF EXISTS leads_agent_id_fkey;
ALTER TABLE IF EXISTS ONLY public.lead_activities DROP CONSTRAINT IF EXISTS lead_activities_lead_id_fkey;
ALTER TABLE IF EXISTS ONLY public.invoice_payments DROP CONSTRAINT IF EXISTS invoice_payments_payment_id_fkey;
ALTER TABLE IF EXISTS ONLY public.invoice_payments DROP CONSTRAINT IF EXISTS invoice_payments_invoice_id_fkey;
ALTER TABLE IF EXISTS ONLY public.documents DROP CONSTRAINT IF EXISTS documents_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.documents DROP CONSTRAINT IF EXISTS documents_reviewed_by_fkey;
ALTER TABLE IF EXISTS ONLY public.documents DROP CONSTRAINT IF EXISTS documents_property_id_fkey;
ALTER TABLE IF EXISTS ONLY public.disputes DROP CONSTRAINT IF EXISTS disputes_payment_id_fkey;
ALTER TABLE IF EXISTS ONLY public.disputes DROP CONSTRAINT IF EXISTS disputes_organization_id_fkey;
ALTER TABLE IF EXISTS ONLY public.disputes DROP CONSTRAINT IF EXISTS disputes_opened_by_fkey;
ALTER TABLE IF EXISTS ONLY public.disputes DROP CONSTRAINT IF EXISTS disputes_assigned_to_fkey;
ALTER TABLE IF EXISTS ONLY public.dispute_messages DROP CONSTRAINT IF EXISTS dispute_messages_sender_id_fkey;
ALTER TABLE IF EXISTS ONLY public.dispute_messages DROP CONSTRAINT IF EXISTS dispute_messages_dispute_id_fkey;
ALTER TABLE IF EXISTS ONLY public.customer_payment_methods DROP CONSTRAINT IF EXISTS customer_payment_methods_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.customer_payment_methods DROP CONSTRAINT IF EXISTS customer_payment_methods_organization_id_fkey;
ALTER TABLE IF EXISTS ONLY public.conversations DROP CONSTRAINT IF EXISTS conversations_organization_id_fkey;
ALTER TABLE IF EXISTS ONLY public.conversations DROP CONSTRAINT IF EXISTS conversations_created_by_fkey;
ALTER TABLE IF EXISTS ONLY public.conversation_participants DROP CONSTRAINT IF EXISTS conversation_participants_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.conversation_participants DROP CONSTRAINT IF EXISTS conversation_participants_organization_id_fkey;
ALTER TABLE IF EXISTS ONLY public.conversation_participants DROP CONSTRAINT IF EXISTS conversation_participants_conversation_id_fkey;
ALTER TABLE IF EXISTS ONLY public.contracts DROP CONSTRAINT IF EXISTS contracts_tenancy_id_fkey;
ALTER TABLE IF EXISTS ONLY public.contracts DROP CONSTRAINT IF EXISTS contracts_property_id_fkey;
ALTER TABLE IF EXISTS ONLY public.contracts DROP CONSTRAINT IF EXISTS contracts_organization_id_fkey;
ALTER TABLE IF EXISTS ONLY public.contracts DROP CONSTRAINT IF EXISTS contracts_listing_id_fkey;
ALTER TABLE IF EXISTS ONLY public.contracts DROP CONSTRAINT IF EXISTS contracts_document_id_fkey;
ALTER TABLE IF EXISTS ONLY public.contracts DROP CONSTRAINT IF EXISTS contracts_created_by_fkey;
ALTER TABLE IF EXISTS ONLY public.contractors DROP CONSTRAINT IF EXISTS contractors_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.contractors DROP CONSTRAINT IF EXISTS contractors_organization_id_fkey;
ALTER TABLE IF EXISTS ONLY public.contract_signatures DROP CONSTRAINT IF EXISTS contract_signatures_contract_party_id_fkey;
ALTER TABLE IF EXISTS ONLY public.contract_parties DROP CONSTRAINT IF EXISTS contract_parties_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.contract_parties DROP CONSTRAINT IF EXISTS contract_parties_contract_id_fkey;
ALTER TABLE IF EXISTS public.audit_logs DROP CONSTRAINT IF EXISTS audit_logs_changed_by_fkey;
ALTER TABLE IF EXISTS ONLY public.api_keys DROP CONSTRAINT IF EXISTS api_keys_organization_id_fkey;
ALTER TABLE IF EXISTS ONLY public.api_keys DROP CONSTRAINT IF EXISTS api_keys_created_by_fkey;
DROP TRIGGER IF EXISTS trigger_payments_success ON public.payments;
DROP TRIGGER IF EXISTS trigger_init_org_receipt_sequence ON public.organizations;
DROP TRIGGER IF EXISTS trigger_drop_org_receipt_sequence ON public.organizations;
DROP TRIGGER IF EXISTS trg_validate_payment_matches_listing ON public.payments;
DROP TRIGGER IF EXISTS trg_sale_details_required ON public.properties;
DROP TRIGGER IF EXISTS trg_resolve_contract_property ON public.contracts;
DROP TRIGGER IF EXISTS trg_enforce_message_org ON public.messages;
DROP TRIGGER IF EXISTS trg_enforce_listing_kind_rules ON public.property_listings;
DROP TRIGGER IF EXISTS trg_bump_last_message ON public.messages;
DROP TRIGGER IF EXISTS set_updated_at_wallet_accounts ON public.wallet_accounts;
DROP TRIGGER IF EXISTS set_updated_at_users ON public.users;
DROP TRIGGER IF EXISTS set_updated_at_tenancies ON public.tenancies;
DROP TRIGGER IF EXISTS set_updated_at_support_tickets ON public.support_tickets;
DROP TRIGGER IF EXISTS set_updated_at_sms_templates ON public.sms_templates;
DROP TRIGGER IF EXISTS set_updated_at_saved_listings ON public.saved_listings;
DROP TRIGGER IF EXISTS set_updated_at_rental_applications ON public.rental_applications;
DROP TRIGGER IF EXISTS set_updated_at_rent_invoices ON public.rent_invoices;
DROP TRIGGER IF EXISTS set_updated_at_property_viewings ON public.property_viewings;
DROP TRIGGER IF EXISTS set_updated_at_property_sale_disclosures ON public.property_sale_disclosures;
DROP TRIGGER IF EXISTS set_updated_at_property_sale_details ON public.property_sale_details;
DROP TRIGGER IF EXISTS set_updated_at_property_media ON public.property_media;
DROP TRIGGER IF EXISTS set_updated_at_property_listings ON public.property_listings;
DROP TRIGGER IF EXISTS set_updated_at_properties ON public.properties;
DROP TRIGGER IF EXISTS set_updated_at_platform_settings ON public.platform_settings;
DROP TRIGGER IF EXISTS set_updated_at_payouts ON public.payouts;
DROP TRIGGER IF EXISTS set_updated_at_payout_accounts ON public.payout_accounts;
DROP TRIGGER IF EXISTS set_updated_at_payments ON public.payments;
DROP TRIGGER IF EXISTS set_updated_at_organizations ON public.organizations;
DROP TRIGGER IF EXISTS set_updated_at_notifications ON public.notifications;
DROP TRIGGER IF EXISTS set_updated_at_messages ON public.messages;
DROP TRIGGER IF EXISTS set_updated_at_maintenance_requests ON public.maintenance_requests;
DROP TRIGGER IF EXISTS set_updated_at_leads ON public.leads;
DROP TRIGGER IF EXISTS set_updated_at_email_templates ON public.email_templates;
DROP TRIGGER IF EXISTS set_updated_at_documents ON public.documents;
DROP TRIGGER IF EXISTS set_updated_at_disputes ON public.disputes;
DROP TRIGGER IF EXISTS set_updated_at_customer_payment_methods ON public.customer_payment_methods;
DROP TRIGGER IF EXISTS set_updated_at_conversations ON public.conversations;
DROP TRIGGER IF EXISTS set_updated_at_contracts ON public.contracts;
DROP TRIGGER IF EXISTS set_updated_at_contractors ON public.contractors;
DROP TRIGGER IF EXISTS set_updated_at_api_keys ON public.api_keys;
DROP TRIGGER IF EXISTS audit_wallet_transactions ON public.wallet_transactions;
DROP TRIGGER IF EXISTS audit_wallet_accounts ON public.wallet_accounts;
DROP TRIGGER IF EXISTS audit_users ON public.users;
DROP TRIGGER IF EXISTS audit_tenancies ON public.tenancies;
DROP TRIGGER IF EXISTS audit_support_tickets ON public.support_tickets;
DROP TRIGGER IF EXISTS audit_sms_templates ON public.sms_templates;
DROP TRIGGER IF EXISTS audit_saved_listings ON public.saved_listings;
DROP TRIGGER IF EXISTS audit_rental_applications ON public.rental_applications;
DROP TRIGGER IF EXISTS audit_rent_invoices ON public.rent_invoices;
DROP TRIGGER IF EXISTS audit_property_viewings ON public.property_viewings;
DROP TRIGGER IF EXISTS audit_property_sale_disclosures ON public.property_sale_disclosures;
DROP TRIGGER IF EXISTS audit_property_sale_details ON public.property_sale_details;
DROP TRIGGER IF EXISTS audit_property_media ON public.property_media;
DROP TRIGGER IF EXISTS audit_property_listings ON public.property_listings;
DROP TRIGGER IF EXISTS audit_properties ON public.properties;
DROP TRIGGER IF EXISTS audit_platform_settings ON public.platform_settings;
DROP TRIGGER IF EXISTS audit_payouts ON public.payouts;
DROP TRIGGER IF EXISTS audit_payout_accounts ON public.payout_accounts;
DROP TRIGGER IF EXISTS audit_payments ON public.payments;
DROP TRIGGER IF EXISTS audit_payment_splits ON public.payment_splits;
DROP TRIGGER IF EXISTS audit_organizations ON public.organizations;
DROP TRIGGER IF EXISTS audit_notifications ON public.notifications;
DROP TRIGGER IF EXISTS audit_messages ON public.messages;
DROP TRIGGER IF EXISTS audit_message_attachments ON public.message_attachments;
DROP TRIGGER IF EXISTS audit_maintenance_updates ON public.maintenance_updates;
DROP TRIGGER IF EXISTS audit_maintenance_requests ON public.maintenance_requests;
DROP TRIGGER IF EXISTS audit_maintenance_attachments ON public.maintenance_attachments;
DROP TRIGGER IF EXISTS audit_leads ON public.leads;
DROP TRIGGER IF EXISTS audit_lead_activities ON public.lead_activities;
DROP TRIGGER IF EXISTS audit_invoice_payments ON public.invoice_payments;
DROP TRIGGER IF EXISTS audit_email_templates ON public.email_templates;
DROP TRIGGER IF EXISTS audit_documents ON public.documents;
DROP TRIGGER IF EXISTS audit_disputes ON public.disputes;
DROP TRIGGER IF EXISTS audit_dispute_messages ON public.dispute_messages;
DROP TRIGGER IF EXISTS audit_customer_payment_methods ON public.customer_payment_methods;
DROP TRIGGER IF EXISTS audit_conversations ON public.conversations;
DROP TRIGGER IF EXISTS audit_conversation_participants ON public.conversation_participants;
DROP TRIGGER IF EXISTS audit_contracts ON public.contracts;
DROP TRIGGER IF EXISTS audit_contractors ON public.contractors;
DROP TRIGGER IF EXISTS audit_contract_signatures ON public.contract_signatures;
DROP TRIGGER IF EXISTS audit_contract_parties ON public.contract_parties;
DROP TRIGGER IF EXISTS audit_api_keys ON public.api_keys;
DROP INDEX IF EXISTS public.uniq_wallet_tx_payment_credit;
DROP INDEX IF EXISTS public.uniq_sale_disclosures_property_type_ref;
DROP INDEX IF EXISTS public.uniq_rent_invoice_org_number;
DROP INDEX IF EXISTS public.uniq_cust_pm_single_default;
DROP INDEX IF EXISTS public.uniq_application_per_listing_user;
DROP INDEX IF EXISTS public.uniq_active_tenancy;
DROP INDEX IF EXISTS public.idx_wallet_tx_reference;
DROP INDEX IF EXISTS public.idx_wallet_tx_account_time;
DROP INDEX IF EXISTS public.idx_users_organization_id;
DROP INDEX IF EXISTS public.idx_users_email_unique;
DROP INDEX IF EXISTS public.idx_tenancies_tenant_id;
DROP INDEX IF EXISTS public.idx_tenancies_property_id;
DROP INDEX IF EXISTS public.idx_tenancies_next_due;
DROP INDEX IF EXISTS public.idx_support_tickets_user;
DROP INDEX IF EXISTS public.idx_support_tickets_status;
DROP INDEX IF EXISTS public.idx_sms_templates_org;
DROP INDEX IF EXISTS public.idx_saved_listings_user;
DROP INDEX IF EXISTS public.idx_saved_listings_org;
DROP INDEX IF EXISTS public.idx_saved_listings_listing;
DROP INDEX IF EXISTS public.idx_sale_disclosures_property;
DROP INDEX IF EXISTS public.idx_sale_disclosures_doc_type;
DROP INDEX IF EXISTS public.idx_rental_applications_listing;
DROP INDEX IF EXISTS public.idx_rental_applications_applicant;
DROP INDEX IF EXISTS public.idx_rent_invoices_tenant_due;
DROP INDEX IF EXISTS public.idx_rent_invoices_tenancy;
DROP INDEX IF EXISTS public.idx_rent_invoices_property;
DROP INDEX IF EXISTS public.idx_rent_invoices_org_due;
DROP INDEX IF EXISTS public.idx_property_viewings_tenant;
DROP INDEX IF EXISTS public.idx_property_viewings_listing;
DROP INDEX IF EXISTS public.idx_property_media_property;
DROP INDEX IF EXISTS public.idx_property_media_metadata_gin;
DROP INDEX IF EXISTS public.idx_property_media_cover;
DROP INDEX IF EXISTS public.idx_properties_slug_unique;
DROP INDEX IF EXISTS public.idx_properties_search_vector;
DROP INDEX IF EXISTS public.idx_properties_owner;
DROP INDEX IF EXISTS public.idx_properties_org;
DROP INDEX IF EXISTS public.idx_properties_location;
DROP INDEX IF EXISTS public.idx_properties_default_agent;
DROP INDEX IF EXISTS public.idx_properties_city_price;
DROP INDEX IF EXISTS public.idx_properties_amenities_gin;
DROP INDEX IF EXISTS public.idx_platform_settings_org;
DROP INDEX IF EXISTS public.idx_payouts_user_status;
DROP INDEX IF EXISTS public.idx_payouts_gateway_response_gin;
DROP INDEX IF EXISTS public.idx_payments_tenant_id;
DROP INDEX IF EXISTS public.idx_payments_status_created_at;
DROP INDEX IF EXISTS public.idx_payments_property_id;
DROP INDEX IF EXISTS public.idx_payments_listing_status;
DROP INDEX IF EXISTS public.idx_payments_gateway_response_gin;
DROP INDEX IF EXISTS public.idx_payment_splits_payment;
DROP INDEX IF EXISTS public.idx_payment_splits_beneficiary;
DROP INDEX IF EXISTS public.idx_notifications_user_id;
DROP INDEX IF EXISTS public.idx_notifications_user_created_at;
DROP INDEX IF EXISTS public.idx_msg_attach_org;
DROP INDEX IF EXISTS public.idx_msg_attach_msg;
DROP INDEX IF EXISTS public.idx_messages_sender_time;
DROP INDEX IF EXISTS public.idx_messages_org;
DROP INDEX IF EXISTS public.idx_messages_conv_time;
DROP INDEX IF EXISTS public.idx_maint_updates_req_time;
DROP INDEX IF EXISTS public.idx_maint_updates_org;
DROP INDEX IF EXISTS public.idx_maint_property_status;
DROP INDEX IF EXISTS public.idx_maint_org_status;
DROP INDEX IF EXISTS public.idx_maint_created_by;
DROP INDEX IF EXISTS public.idx_maint_attach_req;
DROP INDEX IF EXISTS public.idx_maint_attach_org;
DROP INDEX IF EXISTS public.idx_maint_assigned_contractor;
DROP INDEX IF EXISTS public.idx_listings_public;
DROP INDEX IF EXISTS public.idx_listings_property_status;
DROP INDEX IF EXISTS public.idx_listings_agent;
DROP INDEX IF EXISTS public.idx_leads_agent_status;
DROP INDEX IF EXISTS public.idx_lead_activities_lead;
DROP INDEX IF EXISTS public.idx_invoice_payments_payment;
DROP INDEX IF EXISTS public.idx_invoice_payments_org;
DROP INDEX IF EXISTS public.idx_invoice_payments_invoice;
DROP INDEX IF EXISTS public.idx_email_templates_org;
DROP INDEX IF EXISTS public.idx_documents_user_id;
DROP INDEX IF EXISTS public.idx_documents_property_id;
DROP INDEX IF EXISTS public.idx_documents_metadata_gin;
DROP INDEX IF EXISTS public.idx_disputes_status;
DROP INDEX IF EXISTS public.idx_dispute_messages_dispute;
DROP INDEX IF EXISTS public.idx_cust_pm_user_default;
DROP INDEX IF EXISTS public.idx_cust_pm_provider;
DROP INDEX IF EXISTS public.idx_cust_pm_org;
DROP INDEX IF EXISTS public.idx_conversations_org_last;
DROP INDEX IF EXISTS public.idx_conv_part_user;
DROP INDEX IF EXISTS public.idx_conv_part_org;
DROP INDEX IF EXISTS public.idx_conv_part_conv;
DROP INDEX IF EXISTS public.idx_contracts_status;
DROP INDEX IF EXISTS public.idx_contracts_property;
DROP INDEX IF EXISTS public.idx_contracts_org_status;
DROP INDEX IF EXISTS public.idx_contractors_user;
DROP INDEX IF EXISTS public.idx_contractors_org;
DROP INDEX IF EXISTS public.idx_contract_signatures_party;
DROP INDEX IF EXISTS public.idx_contract_signatures_org;
DROP INDEX IF EXISTS public.idx_contract_parties_org;
DROP INDEX IF EXISTS public.idx_contract_parties_contract;
DROP INDEX IF EXISTS public.idx_api_keys_org;
ALTER TABLE IF EXISTS ONLY public.wallet_transactions DROP CONSTRAINT IF EXISTS wallet_transactions_pkey;
ALTER TABLE IF EXISTS ONLY public.wallet_accounts DROP CONSTRAINT IF EXISTS wallet_accounts_pkey;
ALTER TABLE IF EXISTS ONLY public.wallet_accounts DROP CONSTRAINT IF EXISTS wallet_accounts_organization_id_user_id_currency_is_platfor_key;
ALTER TABLE IF EXISTS ONLY public.users DROP CONSTRAINT IF EXISTS users_pkey;
ALTER TABLE IF EXISTS ONLY public.payments DROP CONSTRAINT IF EXISTS uniq_transaction_reference;
ALTER TABLE IF EXISTS ONLY public.saved_listings DROP CONSTRAINT IF EXISTS uniq_saved_listing;
ALTER TABLE IF EXISTS ONLY public.invoice_payments DROP CONSTRAINT IF EXISTS uniq_invoice_payment;
ALTER TABLE IF EXISTS ONLY public.tenancies DROP CONSTRAINT IF EXISTS tenancies_pkey;
ALTER TABLE IF EXISTS ONLY public.support_tickets DROP CONSTRAINT IF EXISTS support_tickets_pkey;
ALTER TABLE IF EXISTS ONLY public.sms_templates DROP CONSTRAINT IF EXISTS sms_templates_template_key_key;
ALTER TABLE IF EXISTS ONLY public.sms_templates DROP CONSTRAINT IF EXISTS sms_templates_pkey;
ALTER TABLE IF EXISTS ONLY public.saved_listings DROP CONSTRAINT IF EXISTS saved_listings_pkey;
ALTER TABLE IF EXISTS ONLY public.rental_applications DROP CONSTRAINT IF EXISTS rental_applications_pkey;
ALTER TABLE IF EXISTS ONLY public.rent_invoices DROP CONSTRAINT IF EXISTS rent_invoices_pkey;
ALTER TABLE IF EXISTS ONLY public.property_viewings DROP CONSTRAINT IF EXISTS property_viewings_pkey;
ALTER TABLE IF EXISTS ONLY public.property_sale_disclosures DROP CONSTRAINT IF EXISTS property_sale_disclosures_pkey;
ALTER TABLE IF EXISTS ONLY public.property_sale_details DROP CONSTRAINT IF EXISTS property_sale_details_property_id_key;
ALTER TABLE IF EXISTS ONLY public.property_sale_details DROP CONSTRAINT IF EXISTS property_sale_details_pkey;
ALTER TABLE IF EXISTS ONLY public.property_media DROP CONSTRAINT IF EXISTS property_media_pkey;
ALTER TABLE IF EXISTS ONLY public.property_listings DROP CONSTRAINT IF EXISTS property_listings_pkey;
ALTER TABLE IF EXISTS ONLY public.properties DROP CONSTRAINT IF EXISTS properties_pkey;
ALTER TABLE IF EXISTS ONLY public.platform_settings DROP CONSTRAINT IF EXISTS platform_settings_pkey;
ALTER TABLE IF EXISTS ONLY public.platform_settings DROP CONSTRAINT IF EXISTS platform_settings_key_key;
ALTER TABLE IF EXISTS ONLY public.payouts DROP CONSTRAINT IF EXISTS payouts_pkey;
ALTER TABLE IF EXISTS ONLY public.payout_accounts DROP CONSTRAINT IF EXISTS payout_accounts_user_id_provider_provider_token_key;
ALTER TABLE IF EXISTS ONLY public.payout_accounts DROP CONSTRAINT IF EXISTS payout_accounts_pkey;
ALTER TABLE IF EXISTS ONLY public.payments DROP CONSTRAINT IF EXISTS payments_pkey;
ALTER TABLE IF EXISTS ONLY public.payment_splits DROP CONSTRAINT IF EXISTS payment_splits_pkey;
ALTER TABLE IF EXISTS ONLY public.organizations DROP CONSTRAINT IF EXISTS organizations_pkey;
ALTER TABLE IF EXISTS ONLY public.notifications DROP CONSTRAINT IF EXISTS notifications_pkey;
ALTER TABLE IF EXISTS ONLY public.messages DROP CONSTRAINT IF EXISTS messages_pkey;
ALTER TABLE IF EXISTS ONLY public.message_attachments DROP CONSTRAINT IF EXISTS message_attachments_pkey;
ALTER TABLE IF EXISTS ONLY public.maintenance_updates DROP CONSTRAINT IF EXISTS maintenance_updates_pkey;
ALTER TABLE IF EXISTS ONLY public.maintenance_requests DROP CONSTRAINT IF EXISTS maintenance_requests_pkey;
ALTER TABLE IF EXISTS ONLY public.maintenance_attachments DROP CONSTRAINT IF EXISTS maintenance_attachments_pkey;
ALTER TABLE IF EXISTS ONLY public.leads DROP CONSTRAINT IF EXISTS leads_pkey;
ALTER TABLE IF EXISTS ONLY public.lead_activities DROP CONSTRAINT IF EXISTS lead_activities_pkey;
ALTER TABLE IF EXISTS ONLY public.invoice_payments DROP CONSTRAINT IF EXISTS invoice_payments_pkey;
ALTER TABLE IF EXISTS ONLY public.email_templates DROP CONSTRAINT IF EXISTS email_templates_template_key_key;
ALTER TABLE IF EXISTS ONLY public.email_templates DROP CONSTRAINT IF EXISTS email_templates_pkey;
ALTER TABLE IF EXISTS ONLY public.documents DROP CONSTRAINT IF EXISTS documents_pkey;
ALTER TABLE IF EXISTS ONLY public.disputes DROP CONSTRAINT IF EXISTS disputes_pkey;
ALTER TABLE IF EXISTS ONLY public.disputes DROP CONSTRAINT IF EXISTS disputes_payment_id_key;
ALTER TABLE IF EXISTS ONLY public.dispute_messages DROP CONSTRAINT IF EXISTS dispute_messages_pkey;
ALTER TABLE IF EXISTS ONLY public.customer_payment_methods DROP CONSTRAINT IF EXISTS customer_payment_methods_pkey;
ALTER TABLE IF EXISTS ONLY public.conversations DROP CONSTRAINT IF EXISTS conversations_pkey;
ALTER TABLE IF EXISTS ONLY public.conversation_participants DROP CONSTRAINT IF EXISTS conversation_participants_pkey;
ALTER TABLE IF EXISTS ONLY public.conversation_participants DROP CONSTRAINT IF EXISTS conversation_participants_conversation_id_user_id_key;
ALTER TABLE IF EXISTS ONLY public.contracts DROP CONSTRAINT IF EXISTS contracts_pkey;
ALTER TABLE IF EXISTS ONLY public.contractors DROP CONSTRAINT IF EXISTS contractors_pkey;
ALTER TABLE IF EXISTS ONLY public.contract_signatures DROP CONSTRAINT IF EXISTS contract_signatures_pkey;
ALTER TABLE IF EXISTS ONLY public.contract_parties DROP CONSTRAINT IF EXISTS contract_parties_pkey;
ALTER TABLE IF EXISTS ONLY public.audit_logs_default DROP CONSTRAINT IF EXISTS audit_logs_default_pkey;
ALTER TABLE IF EXISTS ONLY public.audit_logs DROP CONSTRAINT IF EXISTS audit_logs_pkey;
ALTER TABLE IF EXISTS ONLY public.api_keys DROP CONSTRAINT IF EXISTS api_keys_pkey;
DROP VIEW IF EXISTS public.wallet_balances;
DROP TABLE IF EXISTS public.wallet_transactions;
DROP TABLE IF EXISTS public.wallet_accounts;
DROP TABLE IF EXISTS public.users;
DROP TABLE IF EXISTS public.tenancies;
DROP TABLE IF EXISTS public.support_tickets;
DROP TABLE IF EXISTS public.sms_templates;
DROP TABLE IF EXISTS public.saved_listings;
DROP TABLE IF EXISTS public.rental_applications;
DROP TABLE IF EXISTS public.rent_invoices;
DROP SEQUENCE IF EXISTS public.rentease_invoice_seq;
DROP TABLE IF EXISTS public.property_viewings;
DROP TABLE IF EXISTS public.property_sale_disclosures;
DROP TABLE IF EXISTS public.property_sale_details;
DROP TABLE IF EXISTS public.property_media;
DROP TABLE IF EXISTS public.platform_settings;
DROP TABLE IF EXISTS public.payouts;
DROP TABLE IF EXISTS public.payout_accounts;
DROP TABLE IF EXISTS public.payments;
DROP TABLE IF EXISTS public.payment_splits;
DROP TABLE IF EXISTS public.organizations;
DROP SEQUENCE IF EXISTS public.org_1f297ca1_2764_4541_9d2e_00fe49e3d3bc_receipt_seq;
DROP TABLE IF EXISTS public.notifications;
DROP TABLE IF EXISTS public.messages;
DROP TABLE IF EXISTS public.message_attachments;
DROP VIEW IF EXISTS public.marketplace_listings;
DROP TABLE IF EXISTS public.property_listings;
DROP TABLE IF EXISTS public.properties;
DROP TABLE IF EXISTS public.maintenance_updates;
DROP TABLE IF EXISTS public.maintenance_requests;
DROP TABLE IF EXISTS public.maintenance_attachments;
DROP TABLE IF EXISTS public.leads;
DROP TABLE IF EXISTS public.lead_activities;
DROP TABLE IF EXISTS public.invoice_payments;
DROP TABLE IF EXISTS public.email_templates;
DROP TABLE IF EXISTS public.documents;
DROP TABLE IF EXISTS public.disputes;
DROP TABLE IF EXISTS public.dispute_messages;
DROP TABLE IF EXISTS public.customer_payment_methods;
DROP TABLE IF EXISTS public.conversations;
DROP TABLE IF EXISTS public.conversation_participants;
DROP TABLE IF EXISTS public.contracts;
DROP TABLE IF EXISTS public.contractors;
DROP TABLE IF EXISTS public.contract_signatures;
DROP TABLE IF EXISTS public.contract_parties;
DROP TABLE IF EXISTS public.audit_logs_default;
DROP TABLE IF EXISTS public.audit_logs;
DROP TABLE IF EXISTS public.api_keys;
DROP FUNCTION IF EXISTS public.wallet_credit_from_splits(p_payment_id uuid);
DROP FUNCTION IF EXISTS public.validate_payment_matches_listing();
DROP FUNCTION IF EXISTS public.set_updated_at();
DROP FUNCTION IF EXISTS public.resolve_contract_property_id();
DROP FUNCTION IF EXISTS public.rentease_uuid();
DROP FUNCTION IF EXISTS public.payments_success_trigger_fn();
DROP FUNCTION IF EXISTS public.is_property_owner_or_default_agent(p_property_id uuid);
DROP FUNCTION IF EXISTS public.is_listing_participant(p_listing_id uuid);
DROP FUNCTION IF EXISTS public.is_conversation_participant(p_conversation_id uuid);
DROP FUNCTION IF EXISTS public.is_conversation_admin(p_conversation_id uuid);
DROP FUNCTION IF EXISTS public.is_admin();
DROP FUNCTION IF EXISTS public.init_org_receipt_sequence();
DROP FUNCTION IF EXISTS public.generate_receipt(payment_uuid uuid);
DROP FUNCTION IF EXISTS public.generate_payment_splits(p_payment_id uuid);
DROP FUNCTION IF EXISTS public.ensure_wallet_account(p_org uuid, p_user uuid, p_currency character varying, p_is_platform boolean);
DROP FUNCTION IF EXISTS public.enforce_sale_details_present();
DROP FUNCTION IF EXISTS public.enforce_message_org();
DROP FUNCTION IF EXISTS public.enforce_listing_kind_rules();
DROP FUNCTION IF EXISTS public.drop_org_receipt_sequence();
DROP FUNCTION IF EXISTS public.current_user_uuid();
DROP FUNCTION IF EXISTS public.current_user_role();
DROP FUNCTION IF EXISTS public.current_organization_uuid();
DROP FUNCTION IF EXISTS public.can_manage_contract(p_contract_id uuid);
DROP FUNCTION IF EXISTS public.can_access_maintenance_request(p_request_id uuid);
DROP FUNCTION IF EXISTS public.can_access_maintenance(p_property_id uuid, p_created_by uuid);
DROP FUNCTION IF EXISTS public.can_access_contract(p_contract_id uuid);
DROP FUNCTION IF EXISTS public.bump_conversation_last_message();
DROP FUNCTION IF EXISTS public.audit_log_trigger();
DROP TYPE IF EXISTS public.wallet_transaction_type;
DROP TYPE IF EXISTS public.viewing_status;
DROP TYPE IF EXISTS public.viewing_mode;
DROP TYPE IF EXISTS public.verified_status;
DROP TYPE IF EXISTS public.user_role;
DROP TYPE IF EXISTS public.tenancy_status;
DROP TYPE IF EXISTS public.support_status;
DROP TYPE IF EXISTS public.support_priority;
DROP TYPE IF EXISTS public.split_type;
DROP TYPE IF EXISTS public.property_type;
DROP TYPE IF EXISTS public.property_status;
DROP TYPE IF EXISTS public.platform_fee_basis;
DROP TYPE IF EXISTS public.payout_status;
DROP TYPE IF EXISTS public.payment_status;
DROP TYPE IF EXISTS public.payment_method_kind;
DROP TYPE IF EXISTS public.payment_method;
DROP TYPE IF EXISTS public.payment_cycle;
DROP TYPE IF EXISTS public.notification_type;
DROP TYPE IF EXISTS public.media_type;
DROP TYPE IF EXISTS public.maintenance_status;
DROP TYPE IF EXISTS public.maintenance_priority;
DROP TYPE IF EXISTS public.listing_status;
DROP TYPE IF EXISTS public.listing_kind;
DROP TYPE IF EXISTS public.lead_status;
DROP TYPE IF EXISTS public.invoice_status;
DROP TYPE IF EXISTS public.document_type;
DROP TYPE IF EXISTS public.dispute_status;
DROP TYPE IF EXISTS public.contract_status;
DROP TYPE IF EXISTS public.beneficiary_kind;
DROP TYPE IF EXISTS public.audit_operation;
DROP TYPE IF EXISTS public.application_status;
DROP EXTENSION IF EXISTS "uuid-ossp";
DROP EXTENSION IF EXISTS pgcrypto;
DROP EXTENSION IF EXISTS pg_stat_statements;
DROP EXTENSION IF EXISTS earthdistance;
DROP EXTENSION IF EXISTS cube;
-- *not* dropping schema, since initdb creates it
--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS '';


--
-- Name: cube; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS cube WITH SCHEMA public;


--
-- Name: EXTENSION cube; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION cube IS 'data type for multidimensional cubes';


--
-- Name: earthdistance; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS earthdistance WITH SCHEMA public;


--
-- Name: EXTENSION earthdistance; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION earthdistance IS 'calculate great-circle distances on the surface of the Earth';


--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_stat_statements IS 'track planning and execution statistics of all SQL statements executed';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: application_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.application_status AS ENUM (
    'pending',
    'approved',
    'rejected',
    'withdrawn'
);


--
-- Name: audit_operation; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.audit_operation AS ENUM (
    'INSERT',
    'UPDATE',
    'DELETE'
);


--
-- Name: beneficiary_kind; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.beneficiary_kind AS ENUM (
    'user',
    'platform'
);


--
-- Name: contract_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.contract_status AS ENUM (
    'draft',
    'sent',
    'signed',
    'void',
    'expired'
);


--
-- Name: dispute_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.dispute_status AS ENUM (
    'open',
    'under_review',
    'won_by_user',
    'won_by_platform',
    'refunded',
    'closed'
);


--
-- Name: document_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.document_type AS ENUM (
    'government_id',
    'passport',
    'drivers_license',
    'ownership',
    'utility_bill',
    'tenant_id',
    'lease_agreement',
    'title_certificate',
    'survey_plan',
    'deed_of_assignment',
    'purchase_receipt',
    'other'
);


--
-- Name: invoice_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.invoice_status AS ENUM (
    'draft',
    'issued',
    'paid',
    'overdue',
    'void',
    'cancelled'
);


--
-- Name: lead_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.lead_status AS ENUM (
    'new',
    'contacted',
    'qualified',
    'proposal',
    'won',
    'lost'
);


--
-- Name: listing_kind; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.listing_kind AS ENUM (
    'owner_direct',
    'agent_partner',
    'agent_direct'
);


--
-- Name: listing_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.listing_status AS ENUM (
    'draft',
    'pending_owner_approval',
    'active',
    'rejected',
    'paused',
    'expired',
    'cancelled'
);


--
-- Name: maintenance_priority; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.maintenance_priority AS ENUM (
    'low',
    'medium',
    'high',
    'urgent'
);


--
-- Name: maintenance_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.maintenance_status AS ENUM (
    'open',
    'in_progress',
    'on_hold',
    'resolved',
    'cancelled'
);


--
-- Name: media_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.media_type AS ENUM (
    'photo',
    'video',
    'floor_plan',
    'virtual_tour',
    'document'
);


--
-- Name: notification_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.notification_type AS ENUM (
    'payment_due',
    'payment_success',
    'payment_failed',
    'verification',
    'message',
    'listing_activity',
    'tenant_application',
    'maintenance_request',
    'system_alert'
);


--
-- Name: payment_cycle; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.payment_cycle AS ENUM (
    'monthly',
    'quarterly',
    'yearly',
    'biweekly'
);


--
-- Name: payment_method; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.payment_method AS ENUM (
    'card',
    'bank_transfer',
    'wallet'
);


--
-- Name: payment_method_kind; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.payment_method_kind AS ENUM (
    'card',
    'bank_account',
    'wallet'
);


--
-- Name: payment_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.payment_status AS ENUM (
    'pending',
    'successful',
    'failed',
    'refunded',
    'disputed'
);


--
-- Name: payout_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.payout_status AS ENUM (
    'pending',
    'processing',
    'paid',
    'failed',
    'reversed',
    'cancelled'
);


--
-- Name: platform_fee_basis; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.platform_fee_basis AS ENUM (
    'total',
    'base',
    'markup'
);


--
-- Name: property_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.property_status AS ENUM (
    'available',
    'occupied',
    'pending',
    'maintenance',
    'unavailable'
);


--
-- Name: property_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.property_type AS ENUM (
    'rent',
    'sale',
    'short_lease',
    'long_lease'
);


--
-- Name: split_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.split_type AS ENUM (
    'payee',
    'agent_markup',
    'agent_commission',
    'platform_fee'
);


--
-- Name: support_priority; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.support_priority AS ENUM (
    'low',
    'medium',
    'high',
    'urgent'
);


--
-- Name: support_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.support_status AS ENUM (
    'open',
    'in_progress',
    'resolved',
    'closed'
);


--
-- Name: tenancy_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.tenancy_status AS ENUM (
    'active',
    'ended',
    'terminated',
    'pending_start'
);


--
-- Name: user_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.user_role AS ENUM (
    'tenant',
    'landlord',
    'agent',
    'admin'
);


--
-- Name: verified_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.verified_status AS ENUM (
    'pending',
    'verified',
    'rejected',
    'suspended'
);


--
-- Name: viewing_mode; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.viewing_mode AS ENUM (
    'in_person',
    'virtual'
);


--
-- Name: viewing_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.viewing_status AS ENUM (
    'pending',
    'approved',
    'rejected',
    'completed',
    'cancelled'
);


--
-- Name: wallet_transaction_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.wallet_transaction_type AS ENUM (
    'credit_payee',
    'credit_agent_markup',
    'credit_agent_commission',
    'credit_platform_fee',
    'debit_withdrawal',
    'debit_refund_reversal',
    'adjustment'
);


--
-- Name: audit_log_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_log_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    INSERT INTO audit_logs(table_name, record_id, operation, changed_by, change_details)
    VALUES (TG_TABLE_NAME, OLD.id, TG_OP::audit_operation, current_user_uuid(), to_jsonb(OLD));
    RETURN OLD;
  ELSE
    INSERT INTO audit_logs(table_name, record_id, operation, changed_by, change_details)
    VALUES (TG_TABLE_NAME, NEW.id, TG_OP::audit_operation, current_user_uuid(), to_jsonb(NEW));
    RETURN NEW;
  END IF;
END;
$$;


--
-- Name: bump_conversation_last_message(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.bump_conversation_last_message() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  UPDATE conversations
  SET last_message_at = NEW.created_at,
      updated_at = NOW()
  WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$;


--
-- Name: can_access_contract(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_access_contract(p_contract_id uuid) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM contracts c
    WHERE c.id = p_contract_id
      AND c.deleted_at IS NULL
      AND c.organization_id = current_organization_uuid()
      AND (
        is_admin()
        OR c.created_by = current_user_uuid()
        OR is_property_owner_or_default_agent(c.property_id)
        OR EXISTS (
          SELECT 1
          FROM contract_parties cp
          WHERE cp.contract_id = c.id
            AND cp.user_id = current_user_uuid()
        )
      )
  );
$$;


--
-- Name: can_access_maintenance(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_access_maintenance(p_property_id uuid, p_created_by uuid) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT (
    is_admin()
    OR p_created_by = current_user_uuid()
    OR is_property_owner_or_default_agent(p_property_id)
  );
$$;


--
-- Name: can_access_maintenance_request(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_access_maintenance_request(p_request_id uuid) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM maintenance_requests mr
    LEFT JOIN contractors c ON c.id = mr.assigned_contractor_id
    WHERE mr.id = p_request_id
      AND mr.deleted_at IS NULL
      AND mr.organization_id = current_organization_uuid()
      AND (
        is_admin()
        OR mr.created_by = current_user_uuid()
        OR mr.assigned_to_user_id = current_user_uuid()
        OR is_property_owner_or_default_agent(mr.property_id)
        OR (c.user_id IS NOT NULL AND c.user_id = current_user_uuid())
      )
  );
$$;


--
-- Name: can_manage_contract(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_manage_contract(p_contract_id uuid) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM contracts c
    WHERE c.id = p_contract_id
      AND c.deleted_at IS NULL
      AND c.organization_id = current_organization_uuid()
      AND (
        is_admin()
        OR c.created_by = current_user_uuid()
        OR is_property_owner_or_default_agent(c.property_id)
      )
  );
$$;


--
-- Name: current_organization_uuid(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_organization_uuid() RETURNS uuid
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN current_setting('app.current_organization', true)::uuid;
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$$;


--
-- Name: current_user_role(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_user_role() RETURNS public.user_role
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT role
  FROM users
  WHERE id = current_user_uuid()
    AND deleted_at IS NULL;
$$;


--
-- Name: current_user_uuid(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_user_uuid() RETURNS uuid
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN current_setting('app.current_user', true)::uuid;
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$$;


--
-- Name: drop_org_receipt_sequence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.drop_org_receipt_sequence() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE v_seq_name text;
BEGIN
  IF OLD.receipt_sequence IS NOT NULL THEN
    SELECT relname INTO v_seq_name FROM pg_class WHERE oid = OLD.receipt_sequence;
    IF v_seq_name IS NOT NULL THEN
      EXECUTE format('DROP SEQUENCE IF EXISTS %I', v_seq_name);
    END IF;
  END IF;
  RETURN OLD;
END;
$$;


--
-- Name: enforce_listing_kind_rules(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_listing_kind_rules() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_owner UUID;
  v_prop_base NUMERIC(15,2);
  v_prop_org UUID;
BEGIN
  SELECT owner_id, base_price, organization_id
  INTO v_owner, v_prop_base, v_prop_org
  FROM properties
  WHERE id = NEW.property_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Property % not found', NEW.property_id;
  END IF;

  IF NEW.organization_id IS NULL THEN
    NEW.organization_id := v_prop_org;
  END IF;

  -- Hard lock fee settings
  NEW.platform_fee_basis := 'total';
  NEW.platform_fee_percent := 2.5;

  IF NEW.kind = 'owner_direct' THEN
    IF v_owner IS NULL THEN
      RAISE EXCEPTION 'owner_direct listing requires properties.owner_id (landlord user)';
    END IF;

    NEW.agent_id := NULL;
    NEW.payee_user_id := v_owner;

    NEW.requires_owner_approval := FALSE;
    NEW.owner_approved := TRUE;
    NEW.owner_approved_at := COALESCE(NEW.owner_approved_at, NOW());
    NEW.owner_approved_by := COALESCE(NEW.owner_approved_by, NEW.created_by);

    NEW.base_price := COALESCE(NULLIF(NEW.base_price, 0), v_prop_base);
    NEW.listed_price := COALESCE(NULLIF(NEW.listed_price, 0), NEW.base_price);

  ELSIF NEW.kind = 'agent_partner' THEN
    IF NEW.agent_id IS NULL THEN
      RAISE EXCEPTION 'agent_partner listing requires agent_id';
    END IF;
    IF v_owner IS NULL THEN
      RAISE EXCEPTION 'agent_partner listing requires properties.owner_id (landlord must exist)';
    END IF;

    NEW.requires_owner_approval := TRUE;
    NEW.payee_user_id := v_owner;

    -- base price MUST match landlord base
    NEW.base_price := COALESCE(NULLIF(NEW.base_price, 0), v_prop_base);
    IF NEW.base_price <> v_prop_base THEN
      RAISE EXCEPTION 'agent_partner base_price (%) must equal properties.base_price (%)', NEW.base_price, v_prop_base;
    END IF;

    NEW.listed_price := COALESCE(NULLIF(NEW.listed_price, 0), NEW.base_price);

    NEW.owner_approved := COALESCE(NEW.owner_approved, FALSE);
    IF NEW.owner_approved = FALSE AND NEW.status = 'active' THEN
      NEW.status := 'pending_owner_approval';
    END IF;

  ELSIF NEW.kind = 'agent_direct' THEN
    IF NEW.agent_id IS NULL THEN
      RAISE EXCEPTION 'agent_direct listing requires agent_id';
    END IF;

    NEW.payee_user_id := NEW.agent_id;

    NEW.requires_owner_approval := FALSE;
    NEW.owner_approved := TRUE;
    NEW.owner_approved_at := COALESCE(NEW.owner_approved_at, NOW());
    NEW.owner_approved_by := COALESCE(NEW.owner_approved_by, NEW.created_by);

    NEW.base_price := COALESCE(NULLIF(NEW.base_price, 0), v_prop_base);
    NEW.listed_price := COALESCE(NULLIF(NEW.listed_price, 0), NEW.base_price);
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: enforce_message_org(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_message_org() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_org UUID;
BEGIN
  SELECT organization_id INTO v_org
  FROM conversations
  WHERE id = NEW.conversation_id
    AND deleted_at IS NULL;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Conversation not found or deleted: %', NEW.conversation_id;
  END IF;

  NEW.organization_id := v_org;
  RETURN NEW;
END;
$$;


--
-- Name: enforce_sale_details_present(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_sale_details_present() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.type = 'sale' AND NEW.deleted_at IS NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM property_sale_details d
      WHERE d.property_id = NEW.id
    ) THEN
      RAISE EXCEPTION 'Sale property % must have property_sale_details row', NEW.id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: ensure_wallet_account(uuid, uuid, character varying, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_wallet_account(p_org uuid, p_user uuid, p_currency character varying, p_is_platform boolean) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
DECLARE
  v_id UUID;
  v_ccy VARCHAR(3);
BEGIN
  v_ccy := UPPER(COALESCE(p_currency, 'USD'));
  IF v_ccy !~ '^[A-Z]{3}$' THEN
    RAISE EXCEPTION 'Invalid currency code: %', v_ccy;
  END IF;

  SELECT id INTO v_id
  FROM wallet_accounts
  WHERE organization_id = p_org
    AND (
      (p_is_platform = TRUE AND user_id IS NULL AND is_platform_wallet = TRUE)
      OR (p_is_platform = FALSE AND user_id = p_user AND is_platform_wallet = FALSE)
    )
    AND currency = v_ccy
  LIMIT 1;

  IF v_id IS NULL THEN
    INSERT INTO wallet_accounts (organization_id, user_id, currency, is_platform_wallet)
    VALUES (p_org, CASE WHEN p_is_platform THEN NULL ELSE p_user END, v_ccy, p_is_platform)
    RETURNING id INTO v_id;
  END IF;

  RETURN v_id;
END;
$_$;


--
-- Name: generate_payment_splits(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_payment_splits(p_payment_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  pmt payments%ROWTYPE;
  lst property_listings%ROWTYPE;

  v_currency VARCHAR(3);

  v_base NUMERIC(15,2);
  v_listed NUMERIC(15,2);
  v_total NUMERIC(15,2);

  v_markup NUMERIC(15,2);
  v_agent_comm NUMERIC(15,2);
  v_platform_fee NUMERIC(15,2);
  v_payee NUMERIC(15,2);

  v_property_currency VARCHAR(3);
BEGIN
  SELECT * INTO pmt FROM payments WHERE id = p_payment_id;
  IF NOT FOUND THEN RETURN; END IF;

  IF pmt.status <> 'successful' THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM payment_splits WHERE payment_id = pmt.id) THEN
    RETURN;
  END IF;

  SELECT * INTO lst
  FROM property_listings
  WHERE id = pmt.listing_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Listing not found for payment %', pmt.id;
  END IF;

  SELECT currency INTO v_property_currency
  FROM properties
  WHERE id = lst.property_id AND deleted_at IS NULL;

  v_currency := COALESCE(pmt.currency, v_property_currency, 'USD');

  v_base := lst.base_price;
  v_listed := lst.listed_price;
  v_total := pmt.amount;

  v_markup := GREATEST(v_listed - v_base, 0);

  IF lst.agent_id IS NOT NULL THEN
    IF lst.requires_owner_approval = TRUE AND lst.owner_approved = FALSE THEN
      v_agent_comm := 0;
    ELSE
      v_agent_comm := ROUND(v_base * (COALESCE(lst.agent_commission_percent,0) / 100.0), 2);
    END IF;
  ELSE
    v_agent_comm := 0;
  END IF;

  v_platform_fee := ROUND(v_total * 0.025, 2);

  v_payee := ROUND(v_total - v_platform_fee - v_markup - v_agent_comm, 2);
  IF v_payee < 0 THEN
    RAISE EXCEPTION 'Payment splits negative remainder. payment %, total %, fee %, markup %, comm %',
      pmt.id, v_total, v_platform_fee, v_markup, v_agent_comm;
  END IF;

  UPDATE payments
  SET platform_fee_amount = v_platform_fee,
      agent_markup_amount = v_markup,
      agent_commission_amount = v_agent_comm,
      payee_amount = v_payee,
      updated_at = NOW()
  WHERE id = pmt.id;

  INSERT INTO payment_splits(payment_id, split_type, beneficiary_kind, beneficiary_user_id, amount, currency)
  VALUES (pmt.id, 'platform_fee', 'platform', NULL, v_platform_fee, v_currency);

  IF lst.agent_id IS NOT NULL AND v_markup > 0 THEN
    INSERT INTO payment_splits(payment_id, split_type, beneficiary_kind, beneficiary_user_id, amount, currency)
    VALUES (pmt.id, 'agent_markup', 'user', lst.agent_id, v_markup, v_currency);
  END IF;

  IF lst.agent_id IS NOT NULL AND v_agent_comm > 0 THEN
    INSERT INTO payment_splits(payment_id, split_type, beneficiary_kind, beneficiary_user_id, amount, currency)
    VALUES (pmt.id, 'agent_commission', 'user', lst.agent_id, v_agent_comm, v_currency);
  END IF;

  IF lst.payee_user_id IS NULL THEN
    RAISE EXCEPTION 'Listing % missing payee_user_id', lst.id;
  END IF;

  INSERT INTO payment_splits(payment_id, split_type, beneficiary_kind, beneficiary_user_id, amount, currency)
  VALUES (pmt.id, 'payee', 'user', lst.payee_user_id, v_payee, v_currency);
END;
$$;


--
-- Name: generate_receipt(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_receipt(payment_uuid uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_org_id UUID;
  v_new_receipt_no BIGINT;
  v_pdf_url TEXT;
  v_seq regclass;
  v_existing_url TEXT;
  v_existing_no BIGINT;
  v_status payment_status;
BEGIN
  -- lock payment row to avoid double receipt generation
  SELECT p.receipt_pdf_url, p.receipt_number, p.status
    INTO v_existing_url, v_existing_no, v_status
  FROM payments p
  WHERE p.id = payment_uuid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment % not found', payment_uuid;
  END IF;

  IF v_status <> 'successful' THEN
    RAISE EXCEPTION 'Receipt can only be generated for successful payments (% has status %)', payment_uuid, v_status;
  END IF;

  -- idempotent: already generated
  IF v_existing_no IS NOT NULL AND v_existing_url IS NOT NULL THEN
    RETURN v_existing_url;
  END IF;

  SELECT l.organization_id INTO v_org_id
  FROM payments p
  JOIN property_listings l ON p.listing_id = l.id
  WHERE p.id = payment_uuid;

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Organization not found for payment %', payment_uuid;
  END IF;

  SELECT receipt_sequence INTO v_seq
  FROM organizations
  WHERE id = v_org_id;

  IF v_seq IS NULL THEN
    RAISE EXCEPTION 'Receipt sequence not configured for organization %', v_org_id;
  END IF;

  v_new_receipt_no := nextval(v_seq);
  v_pdf_url := 'https://cdn.yourplatform.com/receipts/' || v_org_id || '/' || v_new_receipt_no || '.pdf';

  UPDATE payments
  SET receipt_number = v_new_receipt_no,
      receipt_pdf_url = v_pdf_url,
      receipt_generated = TRUE,
      updated_at = NOW()
  WHERE id = payment_uuid;

  RETURN v_pdf_url;
END;
$$;


--
-- Name: init_org_receipt_sequence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.init_org_receipt_sequence() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_seq_name text;
BEGIN
  IF NEW.id IS NULL THEN
    NEW.id := rentease_uuid(); -- FIX: was gen_random_uuid()
  END IF;

  IF NEW.receipt_sequence IS NULL THEN
    v_seq_name := format('org_%s_receipt_seq', replace(NEW.id::text, '-', '_'));
    EXECUTE format('CREATE SEQUENCE IF NOT EXISTS %I START 1', v_seq_name);
    NEW.receipt_sequence := v_seq_name::regclass;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: is_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_admin() RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM users
    WHERE id = current_user_uuid()
      AND role = 'admin'
      AND deleted_at IS NULL
  );
END;
$$;


--
-- Name: is_conversation_admin(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_conversation_admin(p_conversation_id uuid) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM conversation_participants cp
    JOIN conversations c ON c.id = cp.conversation_id
    WHERE cp.conversation_id = p_conversation_id
      AND cp.user_id = current_user_uuid()
      AND cp.role = 'admin'
      AND c.deleted_at IS NULL
      AND c.organization_id = current_organization_uuid()
  );
$$;


--
-- Name: is_conversation_participant(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_conversation_participant(p_conversation_id uuid) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM conversation_participants cp
    JOIN conversations c ON c.id = cp.conversation_id
    WHERE cp.conversation_id = p_conversation_id
      AND cp.user_id = current_user_uuid()
      AND c.deleted_at IS NULL
      AND c.organization_id = current_organization_uuid()
  );
$$;


--
-- Name: is_listing_participant(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_listing_participant(p_listing_id uuid) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM property_listings l
    JOIN properties p ON p.id = l.property_id
    WHERE l.id = p_listing_id
      AND l.deleted_at IS NULL
      AND p.deleted_at IS NULL
      AND (
        is_admin()
        OR l.created_by = current_user_uuid()
        OR l.agent_id = current_user_uuid()
        OR p.owner_id = current_user_uuid()
        OR l.payee_user_id = current_user_uuid()
      )
  );
$$;


--
-- Name: is_property_owner_or_default_agent(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_property_owner_or_default_agent(p_property_id uuid) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM properties
    WHERE id = p_property_id
      AND deleted_at IS NULL
      AND (
        owner_id = current_user_uuid()
        OR default_agent_id = current_user_uuid()
      )
  );
$$;


--
-- Name: payments_success_trigger_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payments_success_trigger_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.status = 'successful' AND OLD.status IS DISTINCT FROM NEW.status THEN
    PERFORM wallet_credit_from_splits(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: rentease_uuid(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rentease_uuid() RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_hex text;
  v_variant text;
BEGIN
  -- Prefer pgcrypto if available
  BEGIN
    RETURN gen_random_uuid();
  EXCEPTION WHEN undefined_function THEN
    NULL;
  END;

  -- Prefer uuid-ossp if available
  BEGIN
    RETURN uuid_generate_v4();
  EXCEPTION WHEN undefined_function THEN
    NULL;
  END;

  -- Pure fallback (RFC4122-ish v4)
  v_hex := md5(random()::text || clock_timestamp()::text);

  v_variant := substr('89ab', (floor(random()*4)+1)::int, 1);

  RETURN (
    substr(v_hex, 1, 8) || '-' ||
    substr(v_hex, 9, 4) || '-' ||
    '4' || substr(v_hex, 14, 3) || '-' ||
    v_variant || substr(v_hex, 18, 3) || '-' ||
    substr(v_hex, 21, 12)
  )::uuid;
END;
$$;


--
-- Name: resolve_contract_property_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.resolve_contract_property_id() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE v_prop UUID;
BEGIN
  IF NEW.property_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.tenancy_id IS NOT NULL THEN
    SELECT property_id INTO v_prop
    FROM tenancies
    WHERE id = NEW.tenancy_id AND deleted_at IS NULL;
    NEW.property_id := v_prop;

  ELSIF NEW.listing_id IS NOT NULL THEN
    SELECT property_id INTO v_prop
    FROM property_listings
    WHERE id = NEW.listing_id AND deleted_at IS NULL;
    NEW.property_id := v_prop;
  END IF;

  IF NEW.property_id IS NULL THEN
    RAISE EXCEPTION 'contracts.property_id could not be resolved (invalid tenancy_id/listing_id)';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;


--
-- Name: validate_payment_matches_listing(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_payment_matches_listing() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
DECLARE
  v_listed NUMERIC(15,2);
  v_listing_property UUID;
  v_property_currency VARCHAR(3);
BEGIN
  SELECT l.listed_price, l.property_id
    INTO v_listed, v_listing_property
  FROM property_listings l
  WHERE l.id = NEW.listing_id
    AND l.deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment references missing/deleted listing %', NEW.listing_id;
  END IF;

  IF NEW.property_id IS DISTINCT FROM v_listing_property THEN
    RAISE EXCEPTION 'Payment.property_id (%) must match listing.property_id (%)',
      NEW.property_id, v_listing_property;
  END IF;

  IF NEW.amount IS NULL OR NEW.amount <> v_listed THEN
    RAISE EXCEPTION 'Payment.amount (%) must equal listing.listed_price (%)', NEW.amount, v_listed;
  END IF;

  SELECT p.currency
    INTO v_property_currency
  FROM properties p
  WHERE p.id = NEW.property_id
    AND p.deleted_at IS NULL;

  NEW.currency := COALESCE(NEW.currency, v_property_currency);

  IF NEW.currency IS NULL THEN
    RAISE EXCEPTION 'Payment.currency must be provided OR properties.currency must be set for property %', NEW.property_id;
  END IF;

  NEW.currency := UPPER(NEW.currency);
  IF NEW.currency !~ '^[A-Z]{3}$' THEN
    RAISE EXCEPTION 'Invalid currency code: % (expected 3-letter code like USD)', NEW.currency;
  END IF;

  RETURN NEW;
END;
$_$;


--
-- Name: wallet_credit_from_splits(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.wallet_credit_from_splits(p_payment_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  pmt payments%ROWTYPE;
  s RECORD;
  v_org UUID;
  v_wallet UUID;
  v_currency VARCHAR(3);
BEGIN
  SELECT * INTO pmt FROM payments WHERE id = p_payment_id;
  IF NOT FOUND THEN RETURN; END IF;
  IF pmt.status <> 'successful' THEN RETURN; END IF;

  SELECT COALESCE(l.organization_id, current_organization_uuid())
    INTO v_org
  FROM property_listings l
  WHERE l.id = pmt.listing_id;

  v_currency := UPPER(COALESCE(pmt.currency, 'USD'));

  -- Ensure splits exist
  PERFORM generate_payment_splits(pmt.id);

  FOR s IN SELECT * FROM payment_splits WHERE payment_id = pmt.id
  LOOP
    IF s.beneficiary_kind = 'platform' THEN
      v_wallet := ensure_wallet_account(v_org, NULL, v_currency, TRUE);

      INSERT INTO wallet_transactions(
        organization_id, wallet_account_id, txn_type,
        reference_type, reference_id, amount, currency, note
      )
      VALUES (
        v_org, v_wallet, 'credit_platform_fee',
        'payment', pmt.id, s.amount, v_currency,
        'Platform fee from ' || pmt.transaction_reference
      )
      ON CONFLICT DO NOTHING;

    ELSE
      v_wallet := ensure_wallet_account(v_org, s.beneficiary_user_id, v_currency, FALSE);

      INSERT INTO wallet_transactions(
        organization_id, wallet_account_id, txn_type,
        reference_type, reference_id, amount, currency, note
      )
      VALUES (
        v_org, v_wallet,
        CASE
          WHEN s.split_type = 'payee' THEN 'credit_payee'
          WHEN s.split_type = 'agent_markup' THEN 'credit_agent_markup'
          WHEN s.split_type = 'agent_commission' THEN 'credit_agent_commission'
          ELSE 'adjustment'
        END,
        'payment', pmt.id, s.amount, v_currency,
        'Credit from ' || pmt.transaction_reference || ' (' || s.split_type::text || ')'
      )
      ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: api_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_keys (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid() NOT NULL,
    name text NOT NULL,
    key_hash text NOT NULL,
    last_used_at timestamp with time zone,
    revoked_at timestamp with time zone,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.api_keys FORCE ROW LEVEL SECURITY;


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    table_name text NOT NULL,
    record_id uuid,
    operation public.audit_operation NOT NULL,
    changed_by uuid,
    change_details jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
)
PARTITION BY RANGE (created_at);


--
-- Name: audit_logs_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs_default (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    table_name text NOT NULL,
    record_id uuid,
    operation public.audit_operation NOT NULL,
    changed_by uuid,
    change_details jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: contract_parties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contract_parties (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    contract_id uuid NOT NULL,
    user_id uuid,
    external_name text,
    external_email text,
    party_role text NOT NULL,
    must_sign boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid(),
    CONSTRAINT chk_party_identity CHECK (((user_id IS NOT NULL) OR ((external_name IS NOT NULL) AND (external_email IS NOT NULL))))
);

ALTER TABLE ONLY public.contract_parties FORCE ROW LEVEL SECURITY;


--
-- Name: contract_signatures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contract_signatures (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    contract_party_id uuid NOT NULL,
    signed_at timestamp with time zone,
    signature_url text,
    ip_address text,
    user_agent text,
    signature_hash text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid()
);

ALTER TABLE ONLY public.contract_signatures FORCE ROW LEVEL SECURITY;


--
-- Name: contractors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contractors (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid() NOT NULL,
    user_id uuid,
    business_name text,
    full_name text NOT NULL,
    email character varying(100),
    phone character varying(20),
    specialties text[],
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone
);

ALTER TABLE ONLY public.contractors FORCE ROW LEVEL SECURITY;


--
-- Name: contracts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contracts (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid() NOT NULL,
    tenancy_id uuid,
    listing_id uuid,
    property_id uuid,
    title text NOT NULL,
    status public.contract_status DEFAULT 'draft'::public.contract_status,
    document_id uuid,
    sent_at timestamp with time zone,
    signed_at timestamp with time zone,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_contract_target CHECK (((tenancy_id IS NOT NULL) OR (listing_id IS NOT NULL) OR (property_id IS NOT NULL)))
);

ALTER TABLE ONLY public.contracts FORCE ROW LEVEL SECURITY;


--
-- Name: conversation_participants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversation_participants (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    conversation_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role text DEFAULT 'member'::text,
    joined_at timestamp with time zone DEFAULT now() NOT NULL,
    last_read_at timestamp with time zone,
    organization_id uuid DEFAULT public.current_organization_uuid()
);

ALTER TABLE ONLY public.conversation_participants FORCE ROW LEVEL SECURITY;


--
-- Name: conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversations (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid() NOT NULL,
    title text,
    is_group boolean DEFAULT false,
    created_by uuid,
    last_message_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone
);

ALTER TABLE ONLY public.conversations FORCE ROW LEVEL SECURITY;


--
-- Name: customer_payment_methods; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_payment_methods (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid() NOT NULL,
    user_id uuid NOT NULL,
    provider text NOT NULL,
    method_kind public.payment_method_kind NOT NULL,
    provider_token text NOT NULL,
    label text,
    brand text,
    last4 character varying(4),
    exp_month integer,
    exp_year integer,
    billing_address jsonb,
    is_default boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_exp_month CHECK (((exp_month IS NULL) OR ((exp_month >= 1) AND (exp_month <= 12))))
);

ALTER TABLE ONLY public.customer_payment_methods FORCE ROW LEVEL SECURITY;


--
-- Name: dispute_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dispute_messages (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    dispute_id uuid NOT NULL,
    sender_id uuid NOT NULL,
    message text NOT NULL,
    attachments jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.dispute_messages FORCE ROW LEVEL SECURITY;


--
-- Name: disputes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.disputes (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid() NOT NULL,
    payment_id uuid NOT NULL,
    opened_by uuid NOT NULL,
    status public.dispute_status DEFAULT 'open'::public.dispute_status,
    reason text,
    evidence jsonb,
    assigned_to uuid,
    resolved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.disputes FORCE ROW LEVEL SECURITY;


--
-- Name: documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.documents (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    user_id uuid,
    property_id uuid,
    document_type public.document_type NOT NULL,
    document_number character varying(100),
    file_url text NOT NULL,
    file_size bigint,
    mime_type character varying(100),
    metadata jsonb,
    expires_at date,
    approval_status public.verified_status DEFAULT 'pending'::public.verified_status,
    reviewed_by uuid,
    reviewed_at timestamp with time zone,
    review_notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    version integer DEFAULT 1,
    CONSTRAINT chk_document_owner CHECK ((((user_id IS NOT NULL) AND (property_id IS NULL)) OR ((user_id IS NULL) AND (property_id IS NOT NULL))))
);

ALTER TABLE ONLY public.documents FORCE ROW LEVEL SECURITY;


--
-- Name: email_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.email_templates (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    template_key text NOT NULL,
    subject text,
    body text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id uuid
);

ALTER TABLE ONLY public.email_templates FORCE ROW LEVEL SECURITY;


--
-- Name: invoice_payments; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: lead_activities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lead_activities (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    lead_id uuid NOT NULL,
    activity_type text,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.lead_activities FORCE ROW LEVEL SECURITY;


--
-- Name: leads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leads (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    agent_id uuid NOT NULL,
    full_name text,
    email character varying(100),
    phone character varying(20),
    source text,
    status public.lead_status DEFAULT 'new'::public.lead_status,
    budget_min numeric(15,2),
    budget_max numeric(15,2),
    preferred_city text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.leads FORCE ROW LEVEL SECURITY;


--
-- Name: maintenance_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.maintenance_attachments (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    maintenance_request_id uuid NOT NULL,
    file_url text NOT NULL,
    mime_type character varying(100),
    file_size bigint,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid()
);

ALTER TABLE ONLY public.maintenance_attachments FORCE ROW LEVEL SECURITY;


--
-- Name: maintenance_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.maintenance_requests (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid() NOT NULL,
    property_id uuid NOT NULL,
    tenancy_id uuid,
    created_by uuid NOT NULL,
    assigned_contractor_id uuid,
    assigned_to_user_id uuid,
    title text NOT NULL,
    description text,
    priority public.maintenance_priority DEFAULT 'medium'::public.maintenance_priority,
    status public.maintenance_status DEFAULT 'open'::public.maintenance_status,
    scheduled_at timestamp with time zone,
    resolved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone
);

ALTER TABLE ONLY public.maintenance_requests FORCE ROW LEVEL SECURITY;


--
-- Name: maintenance_updates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.maintenance_updates (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    maintenance_request_id uuid NOT NULL,
    user_id uuid NOT NULL,
    note text NOT NULL,
    status_after public.maintenance_status,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid()
);

ALTER TABLE ONLY public.maintenance_updates FORCE ROW LEVEL SECURITY;


--
-- Name: properties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.properties (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid() NOT NULL,
    owner_id uuid,
    owner_external_name text,
    owner_external_phone character varying(20),
    owner_external_email character varying(100),
    default_agent_id uuid,
    title character varying(255) NOT NULL,
    description text,
    type public.property_type NOT NULL,
    base_price numeric(15,2) NOT NULL,
    currency character varying(3) DEFAULT 'USD'::character varying,
    address_line1 character varying(255),
    address_line2 character varying(255),
    city character varying(100),
    state character varying(100),
    country character varying(100),
    postal_code character varying(20),
    latitude numeric(10,8),
    longitude numeric(11,8),
    bedrooms integer,
    bathrooms integer,
    square_meters numeric(10,2),
    year_built integer,
    amenities text[],
    status public.property_status DEFAULT 'available'::public.property_status,
    verification_status public.verified_status DEFAULT 'pending'::public.verified_status,
    slug character varying(300),
    view_count integer DEFAULT 0,
    search_vector tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, (((COALESCE(title, ''::character varying))::text || ' '::text) || COALESCE(description, ''::text)))) STORED,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    version integer DEFAULT 1,
    CONSTRAINT chk_base_price_positive CHECK ((base_price > (0)::numeric)),
    CONSTRAINT chk_bathrooms_positive CHECK (((bathrooms IS NULL) OR (bathrooms >= 0))),
    CONSTRAINT chk_bedrooms_positive CHECK (((bedrooms IS NULL) OR (bedrooms >= 0))),
    CONSTRAINT chk_latitude_valid CHECK (((latitude IS NULL) OR ((latitude >= ('-90'::integer)::numeric) AND (latitude <= (90)::numeric)))),
    CONSTRAINT chk_longitude_valid CHECK (((longitude IS NULL) OR ((longitude >= ('-180'::integer)::numeric) AND (longitude <= (180)::numeric)))),
    CONSTRAINT chk_owner_present CHECK (((owner_id IS NOT NULL) OR (owner_external_name IS NOT NULL)))
);

ALTER TABLE ONLY public.properties FORCE ROW LEVEL SECURITY;


--
-- Name: property_listings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.property_listings (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    organization_id uuid,
    property_id uuid NOT NULL,
    kind public.listing_kind NOT NULL,
    status public.listing_status DEFAULT 'draft'::public.listing_status,
    created_by uuid,
    agent_id uuid,
    payee_user_id uuid,
    base_price numeric(15,2) NOT NULL,
    listed_price numeric(15,2) NOT NULL,
    agent_commission_percent numeric(5,2) DEFAULT 0,
    platform_fee_percent numeric(5,2) DEFAULT 2.5,
    platform_fee_basis public.platform_fee_basis DEFAULT 'total'::public.platform_fee_basis,
    requires_owner_approval boolean DEFAULT false,
    owner_approved boolean DEFAULT false,
    owner_approved_at timestamp with time zone,
    owner_approved_by uuid,
    is_public boolean DEFAULT true,
    public_note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_active_requires_approval CHECK (((status <> 'active'::public.listing_status) OR (requires_owner_approval = false) OR (owner_approved = true))),
    CONSTRAINT chk_commission_percent CHECK (((agent_commission_percent >= (0)::numeric) AND (agent_commission_percent <= (100)::numeric))),
    CONSTRAINT chk_listed_ge_base CHECK ((listed_price >= base_price)),
    CONSTRAINT chk_listing_payee_present CHECK ((payee_user_id IS NOT NULL)),
    CONSTRAINT chk_listing_prices CHECK (((base_price > (0)::numeric) AND (listed_price > (0)::numeric))),
    CONSTRAINT chk_platform_fee_basis_total CHECK ((platform_fee_basis = 'total'::public.platform_fee_basis)),
    CONSTRAINT chk_platform_fee_percent_2_5 CHECK ((platform_fee_percent = 2.5))
);

ALTER TABLE ONLY public.property_listings FORCE ROW LEVEL SECURITY;


--
-- Name: marketplace_listings; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.marketplace_listings WITH (security_invoker='true') AS
 SELECT l.id,
    l.property_id,
    l.kind,
    l.status,
    l.listed_price,
    l.agent_commission_percent,
    l.created_at,
    p.title AS property_title,
    p.description AS property_description,
    p.type AS property_type,
    p.currency AS property_currency,
    p.address_line1,
    p.city,
    p.state,
    p.country,
    p.postal_code,
    p.bedrooms,
    p.bathrooms,
    p.square_meters,
    p.amenities,
    p.latitude,
    p.longitude
   FROM (public.property_listings l
     JOIN public.properties p ON ((p.id = l.property_id)))
  WHERE ((l.deleted_at IS NULL) AND (p.deleted_at IS NULL) AND (l.status = 'active'::public.listing_status) AND (l.is_public = true));


--
-- Name: message_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.message_attachments (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    message_id uuid NOT NULL,
    file_url text NOT NULL,
    mime_type character varying(100),
    file_size bigint,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid()
);

ALTER TABLE ONLY public.message_attachments FORCE ROW LEVEL SECURITY;


--
-- Name: messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.messages (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid() NOT NULL,
    conversation_id uuid NOT NULL,
    sender_id uuid NOT NULL,
    body text,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_message_body_or_metadata CHECK (((body IS NOT NULL) OR (metadata IS NOT NULL)))
);

ALTER TABLE ONLY public.messages FORCE ROW LEVEL SECURITY;


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    user_id uuid NOT NULL,
    type public.notification_type NOT NULL,
    title character varying(255),
    content text NOT NULL,
    data jsonb,
    channel character varying(20) DEFAULT 'push'::character varying,
    sent_at timestamp with time zone,
    delivered_at timestamp with time zone,
    read_at timestamp with time zone,
    retry_count integer DEFAULT 0,
    last_retry_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone,
    deleted_at timestamp with time zone,
    version integer DEFAULT 1
);

ALTER TABLE ONLY public.notifications FORCE ROW LEVEL SECURITY;


--
-- Name: org_1f297ca1_2764_4541_9d2e_00fe49e3d3bc_receipt_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.org_1f297ca1_2764_4541_9d2e_00fe49e3d3bc_receipt_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    name text NOT NULL,
    receipt_sequence regclass,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: payment_splits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_splits (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    payment_id uuid NOT NULL,
    split_type public.split_type NOT NULL,
    beneficiary_kind public.beneficiary_kind NOT NULL,
    beneficiary_user_id uuid,
    amount numeric(15,2) NOT NULL,
    currency character varying(3) DEFAULT 'USD'::character varying,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_platform_no_user CHECK ((((beneficiary_kind = 'platform'::public.beneficiary_kind) AND (beneficiary_user_id IS NULL)) OR ((beneficiary_kind = 'user'::public.beneficiary_kind) AND (beneficiary_user_id IS NOT NULL)))),
    CONSTRAINT chk_split_amount_positive CHECK ((amount >= (0)::numeric))
);

ALTER TABLE ONLY public.payment_splits FORCE ROW LEVEL SECURITY;


--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
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
    CONSTRAINT chk_completed_after_initiated CHECK (((completed_at IS NULL) OR (completed_at >= initiated_at))),
    CONSTRAINT chk_payment_amount_positive CHECK ((amount > (0)::numeric)),
    CONSTRAINT chk_refunded_amount CHECK (((refunded_amount IS NULL) OR (refunded_amount >= (0)::numeric)))
);

ALTER TABLE ONLY public.payments FORCE ROW LEVEL SECURITY;


--
-- Name: payout_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payout_accounts (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid() NOT NULL,
    user_id uuid NOT NULL,
    currency character varying(3) DEFAULT 'USD'::character varying,
    provider text NOT NULL,
    provider_token text NOT NULL,
    label text,
    account_name text,
    bank_name text,
    last4 character varying(4),
    is_default boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone
);

ALTER TABLE ONLY public.payout_accounts FORCE ROW LEVEL SECURITY;


--
-- Name: payouts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payouts (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid() NOT NULL,
    user_id uuid NOT NULL,
    wallet_account_id uuid NOT NULL,
    payout_account_id uuid NOT NULL,
    amount numeric(15,2) NOT NULL,
    currency character varying(3) DEFAULT 'USD'::character varying,
    status public.payout_status DEFAULT 'pending'::public.payout_status,
    gateway_payout_id text,
    gateway_response jsonb,
    requested_at timestamp with time zone DEFAULT now() NOT NULL,
    processed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_payout_amount_positive CHECK ((amount > (0)::numeric))
);

ALTER TABLE ONLY public.payouts FORCE ROW LEVEL SECURITY;


--
-- Name: platform_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_settings (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    key text NOT NULL,
    value jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id uuid
);

ALTER TABLE ONLY public.platform_settings FORCE ROW LEVEL SECURITY;


--
-- Name: property_media; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.property_media (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid() NOT NULL,
    property_id uuid NOT NULL,
    media_type public.media_type NOT NULL,
    url text NOT NULL,
    thumbnail_url text,
    sort_order integer DEFAULT 0,
    is_cover boolean DEFAULT false,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone
);

ALTER TABLE ONLY public.property_media FORCE ROW LEVEL SECURITY;


--
-- Name: property_sale_details; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.property_sale_details (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    property_id uuid NOT NULL,
    title_type text,
    title_number text,
    land_use text,
    plot_size_sq_m numeric(12,2),
    zoning text,
    survey_coordinates jsonb,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.property_sale_details FORCE ROW LEVEL SECURITY;


--
-- Name: property_sale_disclosures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.property_sale_disclosures (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    property_id uuid NOT NULL,
    doc_type public.document_type NOT NULL,
    title text,
    issuer text,
    reference_number text,
    summary text,
    notes text,
    document_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.property_sale_disclosures FORCE ROW LEVEL SECURITY;


--
-- Name: property_viewings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.property_viewings (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    listing_id uuid NOT NULL,
    property_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    scheduled_at timestamp with time zone NOT NULL,
    view_mode public.viewing_mode DEFAULT 'in_person'::public.viewing_mode,
    status public.viewing_status DEFAULT 'pending'::public.viewing_status,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.property_viewings FORCE ROW LEVEL SECURITY;


--
-- Name: rentease_invoice_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rentease_invoice_seq
    START WITH 100000
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rent_invoices; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: rental_applications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rental_applications (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    listing_id uuid NOT NULL,
    property_id uuid NOT NULL,
    applicant_id uuid NOT NULL,
    status public.application_status DEFAULT 'pending'::public.application_status,
    message text,
    monthly_income numeric(15,2),
    move_in_date date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.rental_applications FORCE ROW LEVEL SECURITY;


--
-- Name: saved_listings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.saved_listings (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid() NOT NULL,
    user_id uuid NOT NULL,
    listing_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone
);

ALTER TABLE ONLY public.saved_listings FORCE ROW LEVEL SECURITY;


--
-- Name: sms_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sms_templates (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    template_key text NOT NULL,
    body text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_id uuid
);

ALTER TABLE ONLY public.sms_templates FORCE ROW LEVEL SECURITY;


--
-- Name: support_tickets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.support_tickets (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    user_id uuid,
    subject text NOT NULL,
    description text,
    priority public.support_priority DEFAULT 'medium'::public.support_priority,
    status public.support_status DEFAULT 'open'::public.support_status,
    assigned_to uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    closed_at timestamp with time zone
);

ALTER TABLE ONLY public.support_tickets FORCE ROW LEVEL SECURITY;


--
-- Name: tenancies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenancies (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    property_id uuid NOT NULL,
    listing_id uuid,
    rent_amount numeric(15,2) NOT NULL,
    security_deposit numeric(15,2),
    payment_cycle public.payment_cycle DEFAULT 'monthly'::public.payment_cycle,
    start_date date NOT NULL,
    end_date date,
    next_due_date date NOT NULL,
    notice_period_days integer DEFAULT 30,
    status public.tenancy_status DEFAULT 'active'::public.tenancy_status,
    termination_reason text,
    late_fee_percentage numeric(5,2) DEFAULT 5.0,
    grace_period_days integer DEFAULT 5,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    version integer DEFAULT 1,
    CONSTRAINT chk_dates_valid CHECK (((end_date IS NULL) OR (start_date < end_date))),
    CONSTRAINT chk_next_due_valid CHECK ((next_due_date >= start_date)),
    CONSTRAINT chk_notice_period_range CHECK (((notice_period_days >= 0) AND (notice_period_days <= 365))),
    CONSTRAINT chk_rent_amount_positive CHECK ((rent_amount > (0)::numeric))
);

ALTER TABLE ONLY public.tenancies FORCE ROW LEVEL SECURITY;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid(),
    full_name character varying(100) NOT NULL,
    email character varying(100) NOT NULL,
    phone character varying(20),
    password_hash character varying(255) NOT NULL,
    role public.user_role NOT NULL,
    verified_status public.verified_status DEFAULT 'pending'::public.verified_status,
    profile_image_url text,
    two_factor_enabled boolean DEFAULT false,
    last_login timestamp with time zone,
    failed_login_attempts integer DEFAULT 0,
    account_locked_until timestamp with time zone,
    email_notifications boolean DEFAULT true,
    sms_notifications boolean DEFAULT true,
    push_notifications boolean DEFAULT true,
    logo_url text,
    signature_url text,
    receipt_name character varying(100),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    version integer DEFAULT 1,
    CONSTRAINT chk_email_valid CHECK (((email)::text ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'::text)),
    CONSTRAINT chk_phone_valid CHECK (((phone IS NULL) OR ((phone)::text ~* '^\+?[1-9]\d{1,14}$'::text)))
);


--
-- Name: wallet_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wallet_accounts (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid() NOT NULL,
    user_id uuid,
    currency character varying(3) DEFAULT 'USD'::character varying,
    is_platform_wallet boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.wallet_accounts FORCE ROW LEVEL SECURITY;


--
-- Name: wallet_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wallet_transactions (
    id uuid DEFAULT public.rentease_uuid() NOT NULL,
    organization_id uuid DEFAULT public.current_organization_uuid() NOT NULL,
    wallet_account_id uuid NOT NULL,
    txn_type public.wallet_transaction_type NOT NULL,
    reference_type text,
    reference_id uuid,
    amount numeric(15,2) NOT NULL,
    currency character varying(3) DEFAULT 'USD'::character varying,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.wallet_transactions FORCE ROW LEVEL SECURITY;


--
-- Name: wallet_balances; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.wallet_balances WITH (security_invoker='true') AS
 SELECT wa.id AS wallet_account_id,
    wa.organization_id,
    wa.user_id,
    wa.currency,
    wa.is_platform_wallet,
    COALESCE(sum(wt.amount), (0)::numeric) AS balance
   FROM (public.wallet_accounts wa
     LEFT JOIN public.wallet_transactions wt ON ((wt.wallet_account_id = wa.id)))
  GROUP BY wa.id, wa.organization_id, wa.user_id, wa.currency, wa.is_platform_wallet;


--
-- Name: audit_logs_default; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs ATTACH PARTITION public.audit_logs_default DEFAULT;


--
-- Name: api_keys api_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT api_keys_pkey PRIMARY KEY (id);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id, created_at);


--
-- Name: audit_logs_default audit_logs_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs_default
    ADD CONSTRAINT audit_logs_default_pkey PRIMARY KEY (id, created_at);


--
-- Name: contract_parties contract_parties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_parties
    ADD CONSTRAINT contract_parties_pkey PRIMARY KEY (id);


--
-- Name: contract_signatures contract_signatures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_signatures
    ADD CONSTRAINT contract_signatures_pkey PRIMARY KEY (id);


--
-- Name: contractors contractors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contractors
    ADD CONSTRAINT contractors_pkey PRIMARY KEY (id);


--
-- Name: contracts contracts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_pkey PRIMARY KEY (id);


--
-- Name: conversation_participants conversation_participants_conversation_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_participants
    ADD CONSTRAINT conversation_participants_conversation_id_user_id_key UNIQUE (conversation_id, user_id);


--
-- Name: conversation_participants conversation_participants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_participants
    ADD CONSTRAINT conversation_participants_pkey PRIMARY KEY (id);


--
-- Name: conversations conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_pkey PRIMARY KEY (id);


--
-- Name: customer_payment_methods customer_payment_methods_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_payment_methods
    ADD CONSTRAINT customer_payment_methods_pkey PRIMARY KEY (id);


--
-- Name: dispute_messages dispute_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dispute_messages
    ADD CONSTRAINT dispute_messages_pkey PRIMARY KEY (id);


--
-- Name: disputes disputes_payment_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disputes
    ADD CONSTRAINT disputes_payment_id_key UNIQUE (payment_id);


--
-- Name: disputes disputes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disputes
    ADD CONSTRAINT disputes_pkey PRIMARY KEY (id);


--
-- Name: documents documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_pkey PRIMARY KEY (id);


--
-- Name: email_templates email_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_templates
    ADD CONSTRAINT email_templates_pkey PRIMARY KEY (id);


--
-- Name: email_templates email_templates_template_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_templates
    ADD CONSTRAINT email_templates_template_key_key UNIQUE (template_key);


--
-- Name: invoice_payments invoice_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_payments
    ADD CONSTRAINT invoice_payments_pkey PRIMARY KEY (id);


--
-- Name: lead_activities lead_activities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_activities
    ADD CONSTRAINT lead_activities_pkey PRIMARY KEY (id);


--
-- Name: leads leads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT leads_pkey PRIMARY KEY (id);


--
-- Name: maintenance_attachments maintenance_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_attachments
    ADD CONSTRAINT maintenance_attachments_pkey PRIMARY KEY (id);


--
-- Name: maintenance_requests maintenance_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_requests
    ADD CONSTRAINT maintenance_requests_pkey PRIMARY KEY (id);


--
-- Name: maintenance_updates maintenance_updates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_updates
    ADD CONSTRAINT maintenance_updates_pkey PRIMARY KEY (id);


--
-- Name: message_attachments message_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_attachments
    ADD CONSTRAINT message_attachments_pkey PRIMARY KEY (id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: payment_splits payment_splits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_splits
    ADD CONSTRAINT payment_splits_pkey PRIMARY KEY (id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: payout_accounts payout_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payout_accounts
    ADD CONSTRAINT payout_accounts_pkey PRIMARY KEY (id);


--
-- Name: payout_accounts payout_accounts_user_id_provider_provider_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payout_accounts
    ADD CONSTRAINT payout_accounts_user_id_provider_provider_token_key UNIQUE (user_id, provider, provider_token);


--
-- Name: payouts payouts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payouts
    ADD CONSTRAINT payouts_pkey PRIMARY KEY (id);


--
-- Name: platform_settings platform_settings_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_settings
    ADD CONSTRAINT platform_settings_key_key UNIQUE (key);


--
-- Name: platform_settings platform_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_settings
    ADD CONSTRAINT platform_settings_pkey PRIMARY KEY (id);


--
-- Name: properties properties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.properties
    ADD CONSTRAINT properties_pkey PRIMARY KEY (id);


--
-- Name: property_listings property_listings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_listings
    ADD CONSTRAINT property_listings_pkey PRIMARY KEY (id);


--
-- Name: property_media property_media_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_media
    ADD CONSTRAINT property_media_pkey PRIMARY KEY (id);


--
-- Name: property_sale_details property_sale_details_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_sale_details
    ADD CONSTRAINT property_sale_details_pkey PRIMARY KEY (id);


--
-- Name: property_sale_details property_sale_details_property_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_sale_details
    ADD CONSTRAINT property_sale_details_property_id_key UNIQUE (property_id);


--
-- Name: property_sale_disclosures property_sale_disclosures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_sale_disclosures
    ADD CONSTRAINT property_sale_disclosures_pkey PRIMARY KEY (id);


--
-- Name: property_viewings property_viewings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_viewings
    ADD CONSTRAINT property_viewings_pkey PRIMARY KEY (id);


--
-- Name: rent_invoices rent_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rent_invoices
    ADD CONSTRAINT rent_invoices_pkey PRIMARY KEY (id);


--
-- Name: rental_applications rental_applications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rental_applications
    ADD CONSTRAINT rental_applications_pkey PRIMARY KEY (id);


--
-- Name: saved_listings saved_listings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_listings
    ADD CONSTRAINT saved_listings_pkey PRIMARY KEY (id);


--
-- Name: sms_templates sms_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sms_templates
    ADD CONSTRAINT sms_templates_pkey PRIMARY KEY (id);


--
-- Name: sms_templates sms_templates_template_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sms_templates
    ADD CONSTRAINT sms_templates_template_key_key UNIQUE (template_key);


--
-- Name: support_tickets support_tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_tickets
    ADD CONSTRAINT support_tickets_pkey PRIMARY KEY (id);


--
-- Name: tenancies tenancies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenancies
    ADD CONSTRAINT tenancies_pkey PRIMARY KEY (id);


--
-- Name: invoice_payments uniq_invoice_payment; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_payments
    ADD CONSTRAINT uniq_invoice_payment UNIQUE (invoice_id, payment_id);


--
-- Name: saved_listings uniq_saved_listing; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_listings
    ADD CONSTRAINT uniq_saved_listing UNIQUE (user_id, listing_id);


--
-- Name: payments uniq_transaction_reference; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT uniq_transaction_reference UNIQUE (transaction_reference);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: wallet_accounts wallet_accounts_organization_id_user_id_currency_is_platfor_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_accounts
    ADD CONSTRAINT wallet_accounts_organization_id_user_id_currency_is_platfor_key UNIQUE (organization_id, user_id, currency, is_platform_wallet);


--
-- Name: wallet_accounts wallet_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_accounts
    ADD CONSTRAINT wallet_accounts_pkey PRIMARY KEY (id);


--
-- Name: wallet_transactions wallet_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT wallet_transactions_pkey PRIMARY KEY (id);


--
-- Name: idx_api_keys_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_api_keys_org ON public.api_keys USING btree (organization_id);


--
-- Name: idx_contract_parties_contract; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contract_parties_contract ON public.contract_parties USING btree (contract_id);


--
-- Name: idx_contract_parties_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contract_parties_org ON public.contract_parties USING btree (organization_id);


--
-- Name: idx_contract_signatures_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contract_signatures_org ON public.contract_signatures USING btree (organization_id);


--
-- Name: idx_contract_signatures_party; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contract_signatures_party ON public.contract_signatures USING btree (contract_party_id);


--
-- Name: idx_contractors_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contractors_org ON public.contractors USING btree (organization_id, is_active);


--
-- Name: idx_contractors_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contractors_user ON public.contractors USING btree (user_id);


--
-- Name: idx_contracts_org_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contracts_org_status ON public.contracts USING btree (organization_id, status, created_at DESC);


--
-- Name: idx_contracts_property; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contracts_property ON public.contracts USING btree (property_id);


--
-- Name: idx_contracts_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contracts_status ON public.contracts USING btree (status, created_at DESC);


--
-- Name: idx_conv_part_conv; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_conv_part_conv ON public.conversation_participants USING btree (conversation_id);


--
-- Name: idx_conv_part_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_conv_part_org ON public.conversation_participants USING btree (organization_id);


--
-- Name: idx_conv_part_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_conv_part_user ON public.conversation_participants USING btree (user_id, joined_at DESC);


--
-- Name: idx_conversations_org_last; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_conversations_org_last ON public.conversations USING btree (organization_id, last_message_at DESC);


--
-- Name: idx_cust_pm_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cust_pm_org ON public.customer_payment_methods USING btree (organization_id);


--
-- Name: idx_cust_pm_provider; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cust_pm_provider ON public.customer_payment_methods USING btree (provider, method_kind);


--
-- Name: idx_cust_pm_user_default; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cust_pm_user_default ON public.customer_payment_methods USING btree (user_id, is_default);


--
-- Name: idx_dispute_messages_dispute; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dispute_messages_dispute ON public.dispute_messages USING btree (dispute_id, created_at);


--
-- Name: idx_disputes_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_disputes_status ON public.disputes USING btree (status, created_at);


--
-- Name: idx_documents_metadata_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_documents_metadata_gin ON public.documents USING gin (metadata);


--
-- Name: idx_documents_property_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_documents_property_id ON public.documents USING btree (property_id);


--
-- Name: idx_documents_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_documents_user_id ON public.documents USING btree (user_id);


--
-- Name: idx_email_templates_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_templates_org ON public.email_templates USING btree (organization_id);


--
-- Name: idx_invoice_payments_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoice_payments_invoice ON public.invoice_payments USING btree (invoice_id);


--
-- Name: idx_invoice_payments_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoice_payments_org ON public.invoice_payments USING btree (organization_id);


--
-- Name: idx_invoice_payments_payment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoice_payments_payment ON public.invoice_payments USING btree (payment_id);


--
-- Name: idx_lead_activities_lead; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lead_activities_lead ON public.lead_activities USING btree (lead_id);


--
-- Name: idx_leads_agent_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_agent_status ON public.leads USING btree (agent_id, status);


--
-- Name: idx_listings_agent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_listings_agent ON public.property_listings USING btree (agent_id, status) WHERE (deleted_at IS NULL);


--
-- Name: idx_listings_property_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_listings_property_status ON public.property_listings USING btree (property_id, status);


--
-- Name: idx_listings_public; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_listings_public ON public.property_listings USING btree (status, is_public) WHERE (deleted_at IS NULL);


--
-- Name: idx_maint_assigned_contractor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_maint_assigned_contractor ON public.maintenance_requests USING btree (assigned_contractor_id, status);


--
-- Name: idx_maint_attach_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_maint_attach_org ON public.maintenance_attachments USING btree (organization_id);


--
-- Name: idx_maint_attach_req; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_maint_attach_req ON public.maintenance_attachments USING btree (maintenance_request_id);


--
-- Name: idx_maint_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_maint_created_by ON public.maintenance_requests USING btree (created_by, created_at DESC);


--
-- Name: idx_maint_org_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_maint_org_status ON public.maintenance_requests USING btree (organization_id, status, created_at DESC);


--
-- Name: idx_maint_property_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_maint_property_status ON public.maintenance_requests USING btree (property_id, status, created_at DESC);


--
-- Name: idx_maint_updates_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_maint_updates_org ON public.maintenance_updates USING btree (organization_id);


--
-- Name: idx_maint_updates_req_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_maint_updates_req_time ON public.maintenance_updates USING btree (maintenance_request_id, created_at DESC);


--
-- Name: idx_messages_conv_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_messages_conv_time ON public.messages USING btree (conversation_id, created_at DESC);


--
-- Name: idx_messages_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_messages_org ON public.messages USING btree (organization_id);


--
-- Name: idx_messages_sender_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_messages_sender_time ON public.messages USING btree (sender_id, created_at DESC);


--
-- Name: idx_msg_attach_msg; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_msg_attach_msg ON public.message_attachments USING btree (message_id);


--
-- Name: idx_msg_attach_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_msg_attach_org ON public.message_attachments USING btree (organization_id);


--
-- Name: idx_notifications_user_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_user_created_at ON public.notifications USING btree (user_id, created_at);


--
-- Name: idx_notifications_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_user_id ON public.notifications USING btree (user_id);


--
-- Name: idx_payment_splits_beneficiary; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_splits_beneficiary ON public.payment_splits USING btree (beneficiary_kind, beneficiary_user_id);


--
-- Name: idx_payment_splits_payment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_splits_payment ON public.payment_splits USING btree (payment_id);


--
-- Name: idx_payments_gateway_response_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_gateway_response_gin ON public.payments USING gin (gateway_response);


--
-- Name: idx_payments_listing_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_listing_status ON public.payments USING btree (listing_id, status);


--
-- Name: idx_payments_property_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_property_id ON public.payments USING btree (property_id);


--
-- Name: idx_payments_status_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_status_created_at ON public.payments USING btree (status, created_at);


--
-- Name: idx_payments_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_tenant_id ON public.payments USING btree (tenant_id);


--
-- Name: idx_payouts_gateway_response_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payouts_gateway_response_gin ON public.payouts USING gin (gateway_response);


--
-- Name: idx_payouts_user_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payouts_user_status ON public.payouts USING btree (user_id, status, requested_at);


--
-- Name: idx_platform_settings_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_platform_settings_org ON public.platform_settings USING btree (organization_id);


--
-- Name: idx_properties_amenities_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_properties_amenities_gin ON public.properties USING gin (amenities);


--
-- Name: idx_properties_city_price; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_properties_city_price ON public.properties USING btree (city, base_price);


--
-- Name: idx_properties_default_agent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_properties_default_agent ON public.properties USING btree (default_agent_id);


--
-- Name: idx_properties_location; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_properties_location ON public.properties USING gist (public.ll_to_earth((latitude)::double precision, (longitude)::double precision)) WHERE ((latitude IS NOT NULL) AND (longitude IS NOT NULL));


--
-- Name: idx_properties_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_properties_org ON public.properties USING btree (organization_id);


--
-- Name: idx_properties_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_properties_owner ON public.properties USING btree (owner_id);


--
-- Name: idx_properties_search_vector; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_properties_search_vector ON public.properties USING gin (search_vector);


--
-- Name: idx_properties_slug_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_properties_slug_unique ON public.properties USING btree (slug) WHERE (deleted_at IS NULL);


--
-- Name: idx_property_media_cover; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_property_media_cover ON public.property_media USING btree (property_id, is_cover) WHERE (deleted_at IS NULL);


--
-- Name: idx_property_media_metadata_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_property_media_metadata_gin ON public.property_media USING gin (metadata);


--
-- Name: idx_property_media_property; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_property_media_property ON public.property_media USING btree (property_id, sort_order);


--
-- Name: idx_property_viewings_listing; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_property_viewings_listing ON public.property_viewings USING btree (listing_id, scheduled_at);


--
-- Name: idx_property_viewings_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_property_viewings_tenant ON public.property_viewings USING btree (tenant_id, scheduled_at);


--
-- Name: idx_rent_invoices_org_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rent_invoices_org_due ON public.rent_invoices USING btree (organization_id, due_date, status);


--
-- Name: idx_rent_invoices_property; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rent_invoices_property ON public.rent_invoices USING btree (property_id, due_date);


--
-- Name: idx_rent_invoices_tenancy; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rent_invoices_tenancy ON public.rent_invoices USING btree (tenancy_id, due_date);


--
-- Name: idx_rent_invoices_tenant_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rent_invoices_tenant_due ON public.rent_invoices USING btree (tenant_id, due_date, status);


--
-- Name: idx_rental_applications_applicant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rental_applications_applicant ON public.rental_applications USING btree (applicant_id);


--
-- Name: idx_rental_applications_listing; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rental_applications_listing ON public.rental_applications USING btree (listing_id);


--
-- Name: idx_sale_disclosures_doc_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sale_disclosures_doc_type ON public.property_sale_disclosures USING btree (doc_type);


--
-- Name: idx_sale_disclosures_property; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sale_disclosures_property ON public.property_sale_disclosures USING btree (property_id);


--
-- Name: idx_saved_listings_listing; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_saved_listings_listing ON public.saved_listings USING btree (listing_id);


--
-- Name: idx_saved_listings_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_saved_listings_org ON public.saved_listings USING btree (organization_id);


--
-- Name: idx_saved_listings_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_saved_listings_user ON public.saved_listings USING btree (user_id, created_at DESC);


--
-- Name: idx_sms_templates_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sms_templates_org ON public.sms_templates USING btree (organization_id);


--
-- Name: idx_support_tickets_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_support_tickets_status ON public.support_tickets USING btree (status, priority);


--
-- Name: idx_support_tickets_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_support_tickets_user ON public.support_tickets USING btree (user_id);


--
-- Name: idx_tenancies_next_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tenancies_next_due ON public.tenancies USING btree (next_due_date);


--
-- Name: idx_tenancies_property_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tenancies_property_id ON public.tenancies USING btree (property_id);


--
-- Name: idx_tenancies_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tenancies_tenant_id ON public.tenancies USING btree (tenant_id);


--
-- Name: idx_users_email_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_users_email_unique ON public.users USING btree (email) WHERE (deleted_at IS NULL);


--
-- Name: idx_users_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_organization_id ON public.users USING btree (organization_id);


--
-- Name: idx_wallet_tx_account_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wallet_tx_account_time ON public.wallet_transactions USING btree (wallet_account_id, created_at);


--
-- Name: idx_wallet_tx_reference; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wallet_tx_reference ON public.wallet_transactions USING btree (reference_type, reference_id);


--
-- Name: uniq_active_tenancy; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uniq_active_tenancy ON public.tenancies USING btree (tenant_id, property_id) WHERE ((status = 'active'::public.tenancy_status) AND (deleted_at IS NULL));


--
-- Name: uniq_application_per_listing_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uniq_application_per_listing_user ON public.rental_applications USING btree (listing_id, applicant_id) WHERE (status = ANY (ARRAY['pending'::public.application_status, 'approved'::public.application_status]));


--
-- Name: uniq_cust_pm_single_default; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uniq_cust_pm_single_default ON public.customer_payment_methods USING btree (user_id) WHERE ((is_default = true) AND (deleted_at IS NULL));


--
-- Name: uniq_rent_invoice_org_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uniq_rent_invoice_org_number ON public.rent_invoices USING btree (organization_id, invoice_number) WHERE (deleted_at IS NULL);


--
-- Name: uniq_sale_disclosures_property_type_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uniq_sale_disclosures_property_type_ref ON public.property_sale_disclosures USING btree (property_id, doc_type, COALESCE(reference_number, ''::text));


--
-- Name: uniq_wallet_tx_payment_credit; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uniq_wallet_tx_payment_credit ON public.wallet_transactions USING btree (wallet_account_id, reference_type, reference_id, txn_type) WHERE (reference_type = 'payment'::text);


--
-- Name: audit_logs_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.audit_logs_pkey ATTACH PARTITION public.audit_logs_default_pkey;


--
-- Name: api_keys audit_api_keys; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_api_keys AFTER INSERT OR DELETE OR UPDATE ON public.api_keys FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: contract_parties audit_contract_parties; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_contract_parties AFTER INSERT OR DELETE OR UPDATE ON public.contract_parties FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: contract_signatures audit_contract_signatures; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_contract_signatures AFTER INSERT OR DELETE OR UPDATE ON public.contract_signatures FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: contractors audit_contractors; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_contractors AFTER INSERT OR DELETE OR UPDATE ON public.contractors FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: contracts audit_contracts; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_contracts AFTER INSERT OR DELETE OR UPDATE ON public.contracts FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: conversation_participants audit_conversation_participants; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_conversation_participants AFTER INSERT OR DELETE OR UPDATE ON public.conversation_participants FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: conversations audit_conversations; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_conversations AFTER INSERT OR DELETE OR UPDATE ON public.conversations FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: customer_payment_methods audit_customer_payment_methods; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_customer_payment_methods AFTER INSERT OR DELETE OR UPDATE ON public.customer_payment_methods FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: dispute_messages audit_dispute_messages; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_dispute_messages AFTER INSERT OR DELETE OR UPDATE ON public.dispute_messages FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: disputes audit_disputes; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_disputes AFTER INSERT OR DELETE OR UPDATE ON public.disputes FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: documents audit_documents; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_documents AFTER INSERT OR DELETE OR UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: email_templates audit_email_templates; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_email_templates AFTER INSERT OR DELETE OR UPDATE ON public.email_templates FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: invoice_payments audit_invoice_payments; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_invoice_payments AFTER INSERT OR DELETE OR UPDATE ON public.invoice_payments FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: lead_activities audit_lead_activities; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_lead_activities AFTER INSERT OR DELETE OR UPDATE ON public.lead_activities FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: leads audit_leads; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_leads AFTER INSERT OR DELETE OR UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: maintenance_attachments audit_maintenance_attachments; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_maintenance_attachments AFTER INSERT OR DELETE OR UPDATE ON public.maintenance_attachments FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: maintenance_requests audit_maintenance_requests; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_maintenance_requests AFTER INSERT OR DELETE OR UPDATE ON public.maintenance_requests FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: maintenance_updates audit_maintenance_updates; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_maintenance_updates AFTER INSERT OR DELETE OR UPDATE ON public.maintenance_updates FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: message_attachments audit_message_attachments; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_message_attachments AFTER INSERT OR DELETE OR UPDATE ON public.message_attachments FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: messages audit_messages; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_messages AFTER INSERT OR DELETE OR UPDATE ON public.messages FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: notifications audit_notifications; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_notifications AFTER INSERT OR DELETE OR UPDATE ON public.notifications FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: organizations audit_organizations; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_organizations AFTER INSERT OR DELETE OR UPDATE ON public.organizations FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: payment_splits audit_payment_splits; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_payment_splits AFTER INSERT OR DELETE OR UPDATE ON public.payment_splits FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: payments audit_payments; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_payments AFTER INSERT OR DELETE OR UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: payout_accounts audit_payout_accounts; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_payout_accounts AFTER INSERT OR DELETE OR UPDATE ON public.payout_accounts FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: payouts audit_payouts; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_payouts AFTER INSERT OR DELETE OR UPDATE ON public.payouts FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: platform_settings audit_platform_settings; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_platform_settings AFTER INSERT OR DELETE OR UPDATE ON public.platform_settings FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: properties audit_properties; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_properties AFTER INSERT OR DELETE OR UPDATE ON public.properties FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: property_listings audit_property_listings; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_property_listings AFTER INSERT OR DELETE OR UPDATE ON public.property_listings FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: property_media audit_property_media; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_property_media AFTER INSERT OR DELETE OR UPDATE ON public.property_media FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: property_sale_details audit_property_sale_details; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_property_sale_details AFTER INSERT OR DELETE OR UPDATE ON public.property_sale_details FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: property_sale_disclosures audit_property_sale_disclosures; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_property_sale_disclosures AFTER INSERT OR DELETE OR UPDATE ON public.property_sale_disclosures FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: property_viewings audit_property_viewings; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_property_viewings AFTER INSERT OR DELETE OR UPDATE ON public.property_viewings FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: rent_invoices audit_rent_invoices; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_rent_invoices AFTER INSERT OR DELETE OR UPDATE ON public.rent_invoices FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: rental_applications audit_rental_applications; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_rental_applications AFTER INSERT OR DELETE OR UPDATE ON public.rental_applications FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: saved_listings audit_saved_listings; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_saved_listings AFTER INSERT OR DELETE OR UPDATE ON public.saved_listings FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: sms_templates audit_sms_templates; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_sms_templates AFTER INSERT OR DELETE OR UPDATE ON public.sms_templates FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: support_tickets audit_support_tickets; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_support_tickets AFTER INSERT OR DELETE OR UPDATE ON public.support_tickets FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: tenancies audit_tenancies; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_tenancies AFTER INSERT OR DELETE OR UPDATE ON public.tenancies FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: users audit_users; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_users AFTER INSERT OR DELETE OR UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: wallet_accounts audit_wallet_accounts; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_wallet_accounts AFTER INSERT OR DELETE OR UPDATE ON public.wallet_accounts FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: wallet_transactions audit_wallet_transactions; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_wallet_transactions AFTER INSERT OR DELETE OR UPDATE ON public.wallet_transactions FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();


--
-- Name: api_keys set_updated_at_api_keys; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_api_keys BEFORE UPDATE ON public.api_keys FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: contractors set_updated_at_contractors; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_contractors BEFORE UPDATE ON public.contractors FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: contracts set_updated_at_contracts; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_contracts BEFORE UPDATE ON public.contracts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: conversations set_updated_at_conversations; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_conversations BEFORE UPDATE ON public.conversations FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: customer_payment_methods set_updated_at_customer_payment_methods; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_customer_payment_methods BEFORE UPDATE ON public.customer_payment_methods FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: disputes set_updated_at_disputes; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_disputes BEFORE UPDATE ON public.disputes FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: documents set_updated_at_documents; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_documents BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: email_templates set_updated_at_email_templates; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_email_templates BEFORE UPDATE ON public.email_templates FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: leads set_updated_at_leads; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_leads BEFORE UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: maintenance_requests set_updated_at_maintenance_requests; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_maintenance_requests BEFORE UPDATE ON public.maintenance_requests FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: messages set_updated_at_messages; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_messages BEFORE UPDATE ON public.messages FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: notifications set_updated_at_notifications; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_notifications BEFORE UPDATE ON public.notifications FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: organizations set_updated_at_organizations; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_organizations BEFORE UPDATE ON public.organizations FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: payments set_updated_at_payments; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_payments BEFORE UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: payout_accounts set_updated_at_payout_accounts; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_payout_accounts BEFORE UPDATE ON public.payout_accounts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: payouts set_updated_at_payouts; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_payouts BEFORE UPDATE ON public.payouts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: platform_settings set_updated_at_platform_settings; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_platform_settings BEFORE UPDATE ON public.platform_settings FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: properties set_updated_at_properties; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_properties BEFORE UPDATE ON public.properties FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: property_listings set_updated_at_property_listings; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_property_listings BEFORE UPDATE ON public.property_listings FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: property_media set_updated_at_property_media; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_property_media BEFORE UPDATE ON public.property_media FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: property_sale_details set_updated_at_property_sale_details; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_property_sale_details BEFORE UPDATE ON public.property_sale_details FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: property_sale_disclosures set_updated_at_property_sale_disclosures; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_property_sale_disclosures BEFORE UPDATE ON public.property_sale_disclosures FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: property_viewings set_updated_at_property_viewings; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_property_viewings BEFORE UPDATE ON public.property_viewings FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: rent_invoices set_updated_at_rent_invoices; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_rent_invoices BEFORE UPDATE ON public.rent_invoices FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: rental_applications set_updated_at_rental_applications; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_rental_applications BEFORE UPDATE ON public.rental_applications FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: saved_listings set_updated_at_saved_listings; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_saved_listings BEFORE UPDATE ON public.saved_listings FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: sms_templates set_updated_at_sms_templates; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_sms_templates BEFORE UPDATE ON public.sms_templates FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: support_tickets set_updated_at_support_tickets; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_support_tickets BEFORE UPDATE ON public.support_tickets FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: tenancies set_updated_at_tenancies; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_tenancies BEFORE UPDATE ON public.tenancies FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: users set_updated_at_users; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_users BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: wallet_accounts set_updated_at_wallet_accounts; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_wallet_accounts BEFORE UPDATE ON public.wallet_accounts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: messages trg_bump_last_message; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_bump_last_message AFTER INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION public.bump_conversation_last_message();


--
-- Name: property_listings trg_enforce_listing_kind_rules; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_listing_kind_rules BEFORE INSERT OR UPDATE ON public.property_listings FOR EACH ROW EXECUTE FUNCTION public.enforce_listing_kind_rules();


--
-- Name: messages trg_enforce_message_org; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_message_org BEFORE INSERT OR UPDATE OF conversation_id ON public.messages FOR EACH ROW EXECUTE FUNCTION public.enforce_message_org();


--
-- Name: contracts trg_resolve_contract_property; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_resolve_contract_property BEFORE INSERT OR UPDATE OF tenancy_id, listing_id, property_id ON public.contracts FOR EACH ROW EXECUTE FUNCTION public.resolve_contract_property_id();


--
-- Name: properties trg_sale_details_required; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER trg_sale_details_required AFTER INSERT OR UPDATE OF type, deleted_at ON public.properties DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.enforce_sale_details_present();


--
-- Name: payments trg_validate_payment_matches_listing; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validate_payment_matches_listing BEFORE INSERT OR UPDATE OF listing_id, property_id, amount, currency ON public.payments FOR EACH ROW EXECUTE FUNCTION public.validate_payment_matches_listing();


--
-- Name: organizations trigger_drop_org_receipt_sequence; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_drop_org_receipt_sequence AFTER DELETE ON public.organizations FOR EACH ROW EXECUTE FUNCTION public.drop_org_receipt_sequence();


--
-- Name: organizations trigger_init_org_receipt_sequence; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_init_org_receipt_sequence BEFORE INSERT ON public.organizations FOR EACH ROW EXECUTE FUNCTION public.init_org_receipt_sequence();


--
-- Name: payments trigger_payments_success; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_payments_success AFTER UPDATE OF status ON public.payments FOR EACH ROW WHEN ((new.status = 'successful'::public.payment_status)) EXECUTE FUNCTION public.payments_success_trigger_fn();


--
-- Name: api_keys api_keys_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT api_keys_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: api_keys api_keys_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT api_keys_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: audit_logs audit_logs_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs
    ADD CONSTRAINT audit_logs_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id);


--
-- Name: contract_parties contract_parties_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_parties
    ADD CONSTRAINT contract_parties_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contracts(id) ON DELETE CASCADE;


--
-- Name: contract_parties contract_parties_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_parties
    ADD CONSTRAINT contract_parties_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: contract_signatures contract_signatures_contract_party_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_signatures
    ADD CONSTRAINT contract_signatures_contract_party_id_fkey FOREIGN KEY (contract_party_id) REFERENCES public.contract_parties(id) ON DELETE CASCADE;


--
-- Name: contractors contractors_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contractors
    ADD CONSTRAINT contractors_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: contractors contractors_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contractors
    ADD CONSTRAINT contractors_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: contracts contracts_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: contracts contracts_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.documents(id) ON DELETE SET NULL;


--
-- Name: contracts contracts_listing_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_listing_id_fkey FOREIGN KEY (listing_id) REFERENCES public.property_listings(id) ON DELETE SET NULL;


--
-- Name: contracts contracts_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: contracts contracts_property_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE SET NULL;


--
-- Name: contracts contracts_tenancy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_tenancy_id_fkey FOREIGN KEY (tenancy_id) REFERENCES public.tenancies(id) ON DELETE SET NULL;


--
-- Name: conversation_participants conversation_participants_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_participants
    ADD CONSTRAINT conversation_participants_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE;


--
-- Name: conversation_participants conversation_participants_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_participants
    ADD CONSTRAINT conversation_participants_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: conversation_participants conversation_participants_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_participants
    ADD CONSTRAINT conversation_participants_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: conversations conversations_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: conversations conversations_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: customer_payment_methods customer_payment_methods_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_payment_methods
    ADD CONSTRAINT customer_payment_methods_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: customer_payment_methods customer_payment_methods_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_payment_methods
    ADD CONSTRAINT customer_payment_methods_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: dispute_messages dispute_messages_dispute_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dispute_messages
    ADD CONSTRAINT dispute_messages_dispute_id_fkey FOREIGN KEY (dispute_id) REFERENCES public.disputes(id) ON DELETE CASCADE;


--
-- Name: dispute_messages dispute_messages_sender_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dispute_messages
    ADD CONSTRAINT dispute_messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: disputes disputes_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disputes
    ADD CONSTRAINT disputes_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.users(id);


--
-- Name: disputes disputes_opened_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disputes
    ADD CONSTRAINT disputes_opened_by_fkey FOREIGN KEY (opened_by) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: disputes disputes_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disputes
    ADD CONSTRAINT disputes_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: disputes disputes_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disputes
    ADD CONSTRAINT disputes_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.payments(id) ON DELETE CASCADE;


--
-- Name: documents documents_property_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE CASCADE;


--
-- Name: documents documents_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public.users(id);


--
-- Name: documents documents_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: invoice_payments invoice_payments_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_payments
    ADD CONSTRAINT invoice_payments_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.rent_invoices(id) ON DELETE CASCADE;


--
-- Name: invoice_payments invoice_payments_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_payments
    ADD CONSTRAINT invoice_payments_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.payments(id) ON DELETE RESTRICT;


--
-- Name: lead_activities lead_activities_lead_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_activities
    ADD CONSTRAINT lead_activities_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES public.leads(id) ON DELETE CASCADE;


--
-- Name: leads leads_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT leads_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: maintenance_attachments maintenance_attachments_maintenance_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_attachments
    ADD CONSTRAINT maintenance_attachments_maintenance_request_id_fkey FOREIGN KEY (maintenance_request_id) REFERENCES public.maintenance_requests(id) ON DELETE CASCADE;


--
-- Name: maintenance_requests maintenance_requests_assigned_contractor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_requests
    ADD CONSTRAINT maintenance_requests_assigned_contractor_id_fkey FOREIGN KEY (assigned_contractor_id) REFERENCES public.contractors(id) ON DELETE SET NULL;


--
-- Name: maintenance_requests maintenance_requests_assigned_to_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_requests
    ADD CONSTRAINT maintenance_requests_assigned_to_user_id_fkey FOREIGN KEY (assigned_to_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: maintenance_requests maintenance_requests_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_requests
    ADD CONSTRAINT maintenance_requests_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: maintenance_requests maintenance_requests_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_requests
    ADD CONSTRAINT maintenance_requests_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: maintenance_requests maintenance_requests_property_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_requests
    ADD CONSTRAINT maintenance_requests_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE RESTRICT;


--
-- Name: maintenance_requests maintenance_requests_tenancy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_requests
    ADD CONSTRAINT maintenance_requests_tenancy_id_fkey FOREIGN KEY (tenancy_id) REFERENCES public.tenancies(id) ON DELETE SET NULL;


--
-- Name: maintenance_updates maintenance_updates_maintenance_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_updates
    ADD CONSTRAINT maintenance_updates_maintenance_request_id_fkey FOREIGN KEY (maintenance_request_id) REFERENCES public.maintenance_requests(id) ON DELETE CASCADE;


--
-- Name: maintenance_updates maintenance_updates_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_updates
    ADD CONSTRAINT maintenance_updates_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: message_attachments message_attachments_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_attachments
    ADD CONSTRAINT message_attachments_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.messages(id) ON DELETE CASCADE;


--
-- Name: messages messages_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE;


--
-- Name: messages messages_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: messages messages_sender_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: payment_splits payment_splits_beneficiary_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_splits
    ADD CONSTRAINT payment_splits_beneficiary_user_id_fkey FOREIGN KEY (beneficiary_user_id) REFERENCES public.users(id);


--
-- Name: payment_splits payment_splits_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_splits
    ADD CONSTRAINT payment_splits_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.payments(id) ON DELETE CASCADE;


--
-- Name: payments payments_listing_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_listing_id_fkey FOREIGN KEY (listing_id) REFERENCES public.property_listings(id) ON DELETE RESTRICT;


--
-- Name: payments payments_property_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE RESTRICT;


--
-- Name: payments payments_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.users(id);


--
-- Name: payout_accounts payout_accounts_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payout_accounts
    ADD CONSTRAINT payout_accounts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: payout_accounts payout_accounts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payout_accounts
    ADD CONSTRAINT payout_accounts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: payouts payouts_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payouts
    ADD CONSTRAINT payouts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: payouts payouts_payout_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payouts
    ADD CONSTRAINT payouts_payout_account_id_fkey FOREIGN KEY (payout_account_id) REFERENCES public.payout_accounts(id) ON DELETE RESTRICT;


--
-- Name: payouts payouts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payouts
    ADD CONSTRAINT payouts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: payouts payouts_wallet_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payouts
    ADD CONSTRAINT payouts_wallet_account_id_fkey FOREIGN KEY (wallet_account_id) REFERENCES public.wallet_accounts(id) ON DELETE RESTRICT;


--
-- Name: properties properties_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.properties
    ADD CONSTRAINT properties_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: properties properties_default_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.properties
    ADD CONSTRAINT properties_default_agent_id_fkey FOREIGN KEY (default_agent_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: properties properties_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.properties
    ADD CONSTRAINT properties_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: properties properties_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.properties
    ADD CONSTRAINT properties_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: properties properties_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.properties
    ADD CONSTRAINT properties_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: property_listings property_listings_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_listings
    ADD CONSTRAINT property_listings_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: property_listings property_listings_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_listings
    ADD CONSTRAINT property_listings_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: property_listings property_listings_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_listings
    ADD CONSTRAINT property_listings_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: property_listings property_listings_owner_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_listings
    ADD CONSTRAINT property_listings_owner_approved_by_fkey FOREIGN KEY (owner_approved_by) REFERENCES public.users(id);


--
-- Name: property_listings property_listings_payee_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_listings
    ADD CONSTRAINT property_listings_payee_user_id_fkey FOREIGN KEY (payee_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: property_listings property_listings_property_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_listings
    ADD CONSTRAINT property_listings_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE CASCADE;


--
-- Name: property_media property_media_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_media
    ADD CONSTRAINT property_media_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: property_media property_media_property_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_media
    ADD CONSTRAINT property_media_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE CASCADE;


--
-- Name: property_sale_details property_sale_details_property_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_sale_details
    ADD CONSTRAINT property_sale_details_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE CASCADE;


--
-- Name: property_sale_disclosures property_sale_disclosures_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_sale_disclosures
    ADD CONSTRAINT property_sale_disclosures_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.documents(id) ON DELETE SET NULL;


--
-- Name: property_sale_disclosures property_sale_disclosures_property_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_sale_disclosures
    ADD CONSTRAINT property_sale_disclosures_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE CASCADE;


--
-- Name: property_viewings property_viewings_listing_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_viewings
    ADD CONSTRAINT property_viewings_listing_id_fkey FOREIGN KEY (listing_id) REFERENCES public.property_listings(id) ON DELETE CASCADE;


--
-- Name: property_viewings property_viewings_property_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_viewings
    ADD CONSTRAINT property_viewings_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE CASCADE;


--
-- Name: property_viewings property_viewings_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_viewings
    ADD CONSTRAINT property_viewings_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: rent_invoices rent_invoices_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rent_invoices
    ADD CONSTRAINT rent_invoices_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: rent_invoices rent_invoices_property_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rent_invoices
    ADD CONSTRAINT rent_invoices_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE RESTRICT;


--
-- Name: rent_invoices rent_invoices_tenancy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rent_invoices
    ADD CONSTRAINT rent_invoices_tenancy_id_fkey FOREIGN KEY (tenancy_id) REFERENCES public.tenancies(id) ON DELETE CASCADE;


--
-- Name: rent_invoices rent_invoices_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rent_invoices
    ADD CONSTRAINT rent_invoices_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: rental_applications rental_applications_applicant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rental_applications
    ADD CONSTRAINT rental_applications_applicant_id_fkey FOREIGN KEY (applicant_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: rental_applications rental_applications_listing_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rental_applications
    ADD CONSTRAINT rental_applications_listing_id_fkey FOREIGN KEY (listing_id) REFERENCES public.property_listings(id) ON DELETE CASCADE;


--
-- Name: rental_applications rental_applications_property_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rental_applications
    ADD CONSTRAINT rental_applications_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE CASCADE;


--
-- Name: saved_listings saved_listings_listing_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_listings
    ADD CONSTRAINT saved_listings_listing_id_fkey FOREIGN KEY (listing_id) REFERENCES public.property_listings(id) ON DELETE CASCADE;


--
-- Name: saved_listings saved_listings_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_listings
    ADD CONSTRAINT saved_listings_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: saved_listings saved_listings_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_listings
    ADD CONSTRAINT saved_listings_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: support_tickets support_tickets_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_tickets
    ADD CONSTRAINT support_tickets_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.users(id);


--
-- Name: support_tickets support_tickets_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_tickets
    ADD CONSTRAINT support_tickets_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: tenancies tenancies_listing_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenancies
    ADD CONSTRAINT tenancies_listing_id_fkey FOREIGN KEY (listing_id) REFERENCES public.property_listings(id) ON DELETE SET NULL;


--
-- Name: tenancies tenancies_property_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenancies
    ADD CONSTRAINT tenancies_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE RESTRICT;


--
-- Name: tenancies tenancies_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenancies
    ADD CONSTRAINT tenancies_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: users users_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: users users_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: users users_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: wallet_accounts wallet_accounts_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_accounts
    ADD CONSTRAINT wallet_accounts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: wallet_accounts wallet_accounts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_accounts
    ADD CONSTRAINT wallet_accounts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: wallet_transactions wallet_transactions_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT wallet_transactions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: wallet_transactions wallet_transactions_wallet_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT wallet_transactions_wallet_account_id_fkey FOREIGN KEY (wallet_account_id) REFERENCES public.wallet_accounts(id) ON DELETE CASCADE;


--
-- Name: api_keys; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY;

--
-- Name: api_keys api_keys_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY api_keys_all ON public.api_keys USING ((public.is_admin() AND (organization_id = public.current_organization_uuid()))) WITH CHECK ((public.is_admin() AND (organization_id = public.current_organization_uuid())));


--
-- Name: contract_parties; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contract_parties ENABLE ROW LEVEL SECURITY;

--
-- Name: contract_parties contract_parties_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contract_parties_select ON public.contract_parties FOR SELECT USING (((organization_id = public.current_organization_uuid()) AND public.can_access_contract(contract_id)));


--
-- Name: contract_parties contract_parties_write_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contract_parties_write_delete ON public.contract_parties FOR DELETE USING ((public.is_admin() AND (organization_id = public.current_organization_uuid())));


--
-- Name: contract_parties contract_parties_write_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contract_parties_write_insert ON public.contract_parties FOR INSERT WITH CHECK ((public.is_admin() AND (organization_id = public.current_organization_uuid())));


--
-- Name: contract_parties contract_parties_write_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contract_parties_write_update ON public.contract_parties FOR UPDATE USING ((public.is_admin() AND (organization_id = public.current_organization_uuid()))) WITH CHECK ((public.is_admin() AND (organization_id = public.current_organization_uuid())));


--
-- Name: contract_signatures; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contract_signatures ENABLE ROW LEVEL SECURITY;

--
-- Name: contract_signatures contract_signatures_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contract_signatures_insert ON public.contract_signatures FOR INSERT WITH CHECK (((organization_id = public.current_organization_uuid()) AND (EXISTS ( SELECT 1
   FROM public.contract_parties cp
  WHERE ((cp.id = contract_signatures.contract_party_id) AND ((cp.user_id = public.current_user_uuid()) OR public.is_admin()))))));


--
-- Name: contract_signatures contract_signatures_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contract_signatures_select ON public.contract_signatures FOR SELECT USING (((organization_id = public.current_organization_uuid()) AND (EXISTS ( SELECT 1
   FROM public.contract_parties cp
  WHERE ((cp.id = contract_signatures.contract_party_id) AND public.can_access_contract(cp.contract_id))))));


--
-- Name: contractors; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contractors ENABLE ROW LEVEL SECURITY;

--
-- Name: contractors contractors_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contractors_select ON public.contractors FOR SELECT USING (((deleted_at IS NULL) AND (organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (public.current_user_role() = ANY (ARRAY['landlord'::public.user_role, 'agent'::public.user_role])) OR (user_id = public.current_user_uuid()))));


--
-- Name: contractors contractors_write_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contractors_write_delete ON public.contractors FOR DELETE USING ((public.is_admin() AND (organization_id = public.current_organization_uuid())));


--
-- Name: contractors contractors_write_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contractors_write_insert ON public.contractors FOR INSERT WITH CHECK ((public.is_admin() AND (organization_id = public.current_organization_uuid())));


--
-- Name: contractors contractors_write_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contractors_write_update ON public.contractors FOR UPDATE USING ((public.is_admin() AND (organization_id = public.current_organization_uuid()))) WITH CHECK ((public.is_admin() AND (organization_id = public.current_organization_uuid())));


--
-- Name: contracts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contracts ENABLE ROW LEVEL SECURITY;

--
-- Name: contracts contracts_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contracts_delete ON public.contracts FOR DELETE USING ((public.is_admin() AND (organization_id = public.current_organization_uuid())));


--
-- Name: contracts contracts_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contracts_insert ON public.contracts FOR INSERT WITH CHECK (((organization_id = public.current_organization_uuid()) AND (created_by = public.current_user_uuid())));


--
-- Name: contracts contracts_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contracts_select ON public.contracts FOR SELECT USING (((deleted_at IS NULL) AND (organization_id = public.current_organization_uuid()) AND public.can_access_contract(id)));


--
-- Name: contracts contracts_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contracts_update ON public.contracts FOR UPDATE USING (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (created_by = public.current_user_uuid())))) WITH CHECK (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (created_by = public.current_user_uuid()))));


--
-- Name: conversation_participants conv_part_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY conv_part_delete ON public.conversation_participants FOR DELETE USING (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR public.is_conversation_admin(conversation_id))));


--
-- Name: conversation_participants conv_part_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY conv_part_insert ON public.conversation_participants FOR INSERT WITH CHECK (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (EXISTS ( SELECT 1
   FROM public.conversations c
  WHERE ((c.id = conversation_participants.conversation_id) AND (c.deleted_at IS NULL) AND (c.organization_id = public.current_organization_uuid()) AND ((c.created_by = public.current_user_uuid()) OR public.is_conversation_admin(conversation_participants.conversation_id))))))));


--
-- Name: conversation_participants conv_part_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY conv_part_select ON public.conversation_participants FOR SELECT USING (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR public.is_conversation_participant(conversation_id))));


--
-- Name: conversation_participants conv_part_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY conv_part_update ON public.conversation_participants FOR UPDATE USING (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR public.is_conversation_admin(conversation_id)))) WITH CHECK (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR public.is_conversation_admin(conversation_id))));


--
-- Name: conversation_participants; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;

--
-- Name: conversations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

--
-- Name: conversations conversations_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY conversations_delete ON public.conversations FOR DELETE USING ((public.is_admin() AND (organization_id = public.current_organization_uuid())));


--
-- Name: conversations conversations_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY conversations_insert ON public.conversations FOR INSERT WITH CHECK (((organization_id = public.current_organization_uuid()) AND (created_by = public.current_user_uuid())));


--
-- Name: conversations conversations_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY conversations_select ON public.conversations FOR SELECT USING (((deleted_at IS NULL) AND (organization_id = public.current_organization_uuid()) AND (public.is_admin() OR public.is_conversation_participant(id))));


--
-- Name: conversations conversations_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY conversations_update ON public.conversations FOR UPDATE USING (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (created_by = public.current_user_uuid()) OR public.is_conversation_admin(id)))) WITH CHECK (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (created_by = public.current_user_uuid()) OR public.is_conversation_admin(id))));


--
-- Name: customer_payment_methods cust_pm_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cust_pm_select ON public.customer_payment_methods FOR SELECT USING (((deleted_at IS NULL) AND (organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (user_id = public.current_user_uuid()))));


--
-- Name: customer_payment_methods cust_pm_write_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cust_pm_write_delete ON public.customer_payment_methods FOR DELETE USING (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (user_id = public.current_user_uuid()))));


--
-- Name: customer_payment_methods cust_pm_write_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cust_pm_write_insert ON public.customer_payment_methods FOR INSERT WITH CHECK (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (user_id = public.current_user_uuid()))));


--
-- Name: customer_payment_methods cust_pm_write_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cust_pm_write_update ON public.customer_payment_methods FOR UPDATE USING (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (user_id = public.current_user_uuid())))) WITH CHECK (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (user_id = public.current_user_uuid()))));


--
-- Name: customer_payment_methods; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_payment_methods ENABLE ROW LEVEL SECURITY;

--
-- Name: dispute_messages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.dispute_messages ENABLE ROW LEVEL SECURITY;

--
-- Name: dispute_messages dispute_messages_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY dispute_messages_insert ON public.dispute_messages FOR INSERT WITH CHECK (((sender_id = public.current_user_uuid()) AND (EXISTS ( SELECT 1
   FROM public.disputes d
  WHERE ((d.id = dispute_messages.dispute_id) AND (d.organization_id = public.current_organization_uuid()) AND ((d.opened_by = public.current_user_uuid()) OR public.is_admin() OR (EXISTS ( SELECT 1
           FROM public.payments p
          WHERE ((p.id = d.payment_id) AND (p.deleted_at IS NULL) AND ((p.tenant_id = public.current_user_uuid()) OR public.is_listing_participant(p.listing_id)))))))))));


--
-- Name: dispute_messages dispute_messages_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY dispute_messages_select ON public.dispute_messages FOR SELECT USING ((public.is_admin() OR (EXISTS ( SELECT 1
   FROM public.disputes d
  WHERE ((d.id = dispute_messages.dispute_id) AND (d.organization_id = public.current_organization_uuid()) AND ((d.opened_by = public.current_user_uuid()) OR (EXISTS ( SELECT 1
           FROM public.payments p
          WHERE ((p.id = d.payment_id) AND (p.deleted_at IS NULL) AND ((p.tenant_id = public.current_user_uuid()) OR public.is_listing_participant(p.listing_id)))))))))));


--
-- Name: disputes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.disputes ENABLE ROW LEVEL SECURITY;

--
-- Name: disputes disputes_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY disputes_insert ON public.disputes FOR INSERT WITH CHECK (((organization_id = public.current_organization_uuid()) AND ((opened_by = public.current_user_uuid()) OR public.is_admin())));


--
-- Name: disputes disputes_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY disputes_select ON public.disputes FOR SELECT USING (((organization_id = public.current_organization_uuid()) AND ((opened_by = public.current_user_uuid()) OR public.is_admin() OR (EXISTS ( SELECT 1
   FROM public.payments p
  WHERE ((p.id = disputes.payment_id) AND (p.deleted_at IS NULL) AND ((p.tenant_id = public.current_user_uuid()) OR public.is_listing_participant(p.listing_id))))))));


--
-- Name: disputes disputes_update_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY disputes_update_admin ON public.disputes FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: documents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

--
-- Name: documents documents_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY documents_delete_policy ON public.documents FOR DELETE USING (((deleted_at IS NULL) AND (public.is_admin() OR ((user_id IS NOT NULL) AND (user_id = public.current_user_uuid())) OR ((property_id IS NOT NULL) AND public.is_property_owner_or_default_agent(property_id)))));


--
-- Name: documents documents_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY documents_insert_policy ON public.documents FOR INSERT WITH CHECK ((public.is_admin() OR ((user_id IS NOT NULL) AND (user_id = public.current_user_uuid())) OR ((property_id IS NOT NULL) AND public.is_property_owner_or_default_agent(property_id))));


--
-- Name: documents documents_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY documents_select_policy ON public.documents FOR SELECT USING (((deleted_at IS NULL) AND (public.is_admin() OR ((user_id IS NOT NULL) AND (user_id = public.current_user_uuid())) OR ((property_id IS NOT NULL) AND public.is_property_owner_or_default_agent(property_id)))));


--
-- Name: documents documents_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY documents_update_policy ON public.documents FOR UPDATE USING (((deleted_at IS NULL) AND (public.is_admin() OR ((user_id IS NOT NULL) AND (user_id = public.current_user_uuid())) OR ((property_id IS NOT NULL) AND public.is_property_owner_or_default_agent(property_id))))) WITH CHECK ((public.is_admin() OR ((user_id IS NOT NULL) AND (user_id = public.current_user_uuid())) OR ((property_id IS NOT NULL) AND public.is_property_owner_or_default_agent(property_id))));


--
-- Name: email_templates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.email_templates ENABLE ROW LEVEL SECURITY;

--
-- Name: email_templates email_templates_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY email_templates_all ON public.email_templates USING ((public.is_admin() AND (organization_id = public.current_organization_uuid()))) WITH CHECK ((public.is_admin() AND (organization_id = public.current_organization_uuid())));


--
-- Name: invoice_payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invoice_payments ENABLE ROW LEVEL SECURITY;

--
-- Name: invoice_payments invoice_payments_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY invoice_payments_select ON public.invoice_payments FOR SELECT USING (((organization_id = public.current_organization_uuid()) AND (EXISTS ( SELECT 1
   FROM public.rent_invoices ri
  WHERE ((ri.id = invoice_payments.invoice_id) AND (ri.deleted_at IS NULL) AND (ri.organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (ri.tenant_id = public.current_user_uuid()) OR public.is_property_owner_or_default_agent(ri.property_id)))))));


--
-- Name: invoice_payments invoice_payments_write_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY invoice_payments_write_delete ON public.invoice_payments FOR DELETE USING ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name)));


--
-- Name: invoice_payments invoice_payments_write_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY invoice_payments_write_insert ON public.invoice_payments FOR INSERT WITH CHECK (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (CURRENT_USER = 'rentease_service'::name))));


--
-- Name: invoice_payments invoice_payments_write_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY invoice_payments_write_update ON public.invoice_payments FOR UPDATE USING ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name))) WITH CHECK (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (CURRENT_USER = 'rentease_service'::name))));


--
-- Name: lead_activities; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lead_activities ENABLE ROW LEVEL SECURITY;

--
-- Name: lead_activities lead_activities_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lead_activities_policy ON public.lead_activities USING ((EXISTS ( SELECT 1
   FROM public.leads
  WHERE ((leads.id = lead_activities.lead_id) AND ((leads.agent_id = public.current_user_uuid()) OR public.is_admin()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.leads
  WHERE ((leads.id = lead_activities.lead_id) AND ((leads.agent_id = public.current_user_uuid()) OR public.is_admin())))));


--
-- Name: leads; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;

--
-- Name: leads leads_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leads_policy ON public.leads USING (((agent_id = public.current_user_uuid()) OR public.is_admin())) WITH CHECK (((agent_id = public.current_user_uuid()) OR public.is_admin()));


--
-- Name: property_listings listings_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY listings_delete ON public.property_listings FOR DELETE USING (((organization_id = public.current_organization_uuid()) OR public.is_admin()));


--
-- Name: property_listings listings_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY listings_insert ON public.property_listings FOR INSERT WITH CHECK ((public.is_admin() OR ((created_by = public.current_user_uuid()) AND (((kind = 'owner_direct'::public.listing_kind) AND (EXISTS ( SELECT 1
   FROM public.properties p
  WHERE ((p.id = property_listings.property_id) AND (p.deleted_at IS NULL) AND (p.owner_id = public.current_user_uuid()))))) OR ((kind = 'agent_partner'::public.listing_kind) AND (agent_id = public.current_user_uuid()) AND (EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = public.current_user_uuid()) AND (u.role = 'agent'::public.user_role) AND (u.deleted_at IS NULL)))) AND (EXISTS ( SELECT 1
   FROM public.property_listings ol
  WHERE ((ol.property_id = ol.property_id) AND (ol.deleted_at IS NULL) AND (ol.kind = 'owner_direct'::public.listing_kind) AND (ol.status = 'active'::public.listing_status) AND (ol.is_public = true))))) OR ((kind = 'agent_direct'::public.listing_kind) AND (agent_id = public.current_user_uuid()) AND (EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = public.current_user_uuid()) AND (u.role = 'agent'::public.user_role) AND (u.deleted_at IS NULL)))))))));


--
-- Name: property_listings listings_public_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY listings_public_select ON public.property_listings FOR SELECT USING (((deleted_at IS NULL) AND (((status = 'active'::public.listing_status) AND (is_public = true)) OR public.is_listing_participant(id))));


--
-- Name: property_listings listings_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY listings_update ON public.property_listings FOR UPDATE USING (((organization_id = public.current_organization_uuid()) OR public.is_admin())) WITH CHECK (((organization_id = public.current_organization_uuid()) OR public.is_admin()));


--
-- Name: maintenance_attachments maint_attach_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY maint_attach_insert ON public.maintenance_attachments FOR INSERT WITH CHECK (((organization_id = public.current_organization_uuid()) AND (EXISTS ( SELECT 1
   FROM public.maintenance_requests mr
  WHERE ((mr.id = maintenance_attachments.maintenance_request_id) AND public.can_access_maintenance_request(mr.id))))));


--
-- Name: maintenance_attachments maint_attach_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY maint_attach_select ON public.maintenance_attachments FOR SELECT USING (((organization_id = public.current_organization_uuid()) AND (EXISTS ( SELECT 1
   FROM public.maintenance_requests mr
  WHERE ((mr.id = maintenance_attachments.maintenance_request_id) AND public.can_access_maintenance_request(mr.id))))));


--
-- Name: maintenance_requests maint_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY maint_delete ON public.maintenance_requests FOR DELETE USING ((public.is_admin() AND (organization_id = public.current_organization_uuid())));


--
-- Name: maintenance_requests maint_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY maint_insert ON public.maintenance_requests FOR INSERT WITH CHECK (((organization_id = public.current_organization_uuid()) AND (created_by = public.current_user_uuid())));


--
-- Name: maintenance_requests maint_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY maint_select ON public.maintenance_requests FOR SELECT USING (public.can_access_maintenance_request(id));


--
-- Name: maintenance_requests maint_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY maint_update ON public.maintenance_requests FOR UPDATE USING (public.can_access_maintenance_request(id)) WITH CHECK (public.can_access_maintenance_request(id));


--
-- Name: maintenance_updates maint_updates_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY maint_updates_insert ON public.maintenance_updates FOR INSERT WITH CHECK (((organization_id = public.current_organization_uuid()) AND (user_id = public.current_user_uuid()) AND (EXISTS ( SELECT 1
   FROM public.maintenance_requests mr
  WHERE ((mr.id = maintenance_updates.maintenance_request_id) AND public.can_access_maintenance_request(mr.id))))));


--
-- Name: maintenance_updates maint_updates_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY maint_updates_select ON public.maintenance_updates FOR SELECT USING (((organization_id = public.current_organization_uuid()) AND (EXISTS ( SELECT 1
   FROM public.maintenance_requests mr
  WHERE ((mr.id = maintenance_updates.maintenance_request_id) AND public.can_access_maintenance_request(mr.id))))));


--
-- Name: maintenance_attachments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.maintenance_attachments ENABLE ROW LEVEL SECURITY;

--
-- Name: maintenance_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.maintenance_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: maintenance_updates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.maintenance_updates ENABLE ROW LEVEL SECURITY;

--
-- Name: message_attachments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.message_attachments ENABLE ROW LEVEL SECURITY;

--
-- Name: messages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

--
-- Name: messages messages_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY messages_delete ON public.messages FOR DELETE USING ((public.is_admin() AND (organization_id = public.current_organization_uuid())));


--
-- Name: messages messages_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY messages_insert ON public.messages FOR INSERT WITH CHECK (((sender_id = public.current_user_uuid()) AND (organization_id = public.current_organization_uuid()) AND public.is_conversation_participant(conversation_id)));


--
-- Name: messages messages_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY messages_select ON public.messages FOR SELECT USING (((deleted_at IS NULL) AND (organization_id = public.current_organization_uuid()) AND (public.is_admin() OR public.is_conversation_participant(conversation_id))));


--
-- Name: messages messages_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY messages_update ON public.messages FOR UPDATE USING (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (sender_id = public.current_user_uuid())))) WITH CHECK (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (sender_id = public.current_user_uuid()))));


--
-- Name: message_attachments msg_attach_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY msg_attach_delete ON public.message_attachments FOR DELETE USING ((public.is_admin() AND (organization_id = public.current_organization_uuid())));


--
-- Name: message_attachments msg_attach_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY msg_attach_insert ON public.message_attachments FOR INSERT WITH CHECK (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (EXISTS ( SELECT 1
   FROM public.messages m
  WHERE ((m.id = message_attachments.message_id) AND (m.sender_id = public.current_user_uuid()) AND (m.organization_id = public.current_organization_uuid())))))));


--
-- Name: message_attachments msg_attach_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY msg_attach_select ON public.message_attachments FOR SELECT USING (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (EXISTS ( SELECT 1
   FROM public.messages m
  WHERE ((m.id = message_attachments.message_id) AND (m.deleted_at IS NULL) AND (m.organization_id = public.current_organization_uuid()) AND public.is_conversation_participant(m.conversation_id)))))));


--
-- Name: notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: notifications notifications_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_delete_policy ON public.notifications FOR DELETE USING (((user_id = public.current_user_uuid()) OR public.is_admin()));


--
-- Name: notifications notifications_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_insert_policy ON public.notifications FOR INSERT WITH CHECK (((user_id = public.current_user_uuid()) OR public.is_admin()));


--
-- Name: notifications notifications_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_select_policy ON public.notifications FOR SELECT USING (((user_id = public.current_user_uuid()) OR public.is_admin()));


--
-- Name: notifications notifications_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_update_policy ON public.notifications FOR UPDATE USING (((user_id = public.current_user_uuid()) OR public.is_admin())) WITH CHECK (((user_id = public.current_user_uuid()) OR public.is_admin()));


--
-- Name: payment_splits; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payment_splits ENABLE ROW LEVEL SECURITY;

--
-- Name: payment_splits payment_splits_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payment_splits_delete ON public.payment_splits FOR DELETE USING (public.is_admin());


--
-- Name: payment_splits payment_splits_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payment_splits_insert ON public.payment_splits FOR INSERT WITH CHECK (public.is_admin());


--
-- Name: payment_splits payment_splits_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payment_splits_select ON public.payment_splits FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.payments p
  WHERE ((p.id = payment_splits.payment_id) AND (p.deleted_at IS NULL) AND (public.is_admin() OR (p.tenant_id = public.current_user_uuid()) OR public.is_listing_participant(p.listing_id))))));


--
-- Name: payment_splits payment_splits_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payment_splits_update ON public.payment_splits FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: payment_splits payment_splits_write_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payment_splits_write_delete ON public.payment_splits FOR DELETE USING ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name)));


--
-- Name: payment_splits payment_splits_write_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payment_splits_write_insert ON public.payment_splits FOR INSERT WITH CHECK ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name)));


--
-- Name: payment_splits payment_splits_write_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payment_splits_write_update ON public.payment_splits FOR UPDATE USING ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name))) WITH CHECK ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name)));


--
-- Name: payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

--
-- Name: payments payments_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payments_delete_policy ON public.payments FOR DELETE USING (((deleted_at IS NULL) AND ((tenant_id = public.current_user_uuid()) OR public.is_admin())));


--
-- Name: payments payments_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payments_insert_policy ON public.payments FOR INSERT WITH CHECK (((tenant_id = public.current_user_uuid()) OR public.is_admin()));


--
-- Name: payments payments_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payments_select_policy ON public.payments FOR SELECT USING (((deleted_at IS NULL) AND ((tenant_id = public.current_user_uuid()) OR public.is_listing_participant(listing_id) OR public.is_admin())));


--
-- Name: payments payments_service_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payments_service_update ON public.payments FOR UPDATE USING ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name))) WITH CHECK ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name)));


--
-- Name: payments payments_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payments_update_policy ON public.payments FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: payout_accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payout_accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: payout_accounts payout_accounts_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payout_accounts_delete ON public.payout_accounts FOR DELETE USING (((user_id = public.current_user_uuid()) OR public.is_admin()));


--
-- Name: payout_accounts payout_accounts_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payout_accounts_insert ON public.payout_accounts FOR INSERT WITH CHECK (((user_id = public.current_user_uuid()) OR public.is_admin()));


--
-- Name: payout_accounts payout_accounts_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payout_accounts_select ON public.payout_accounts FOR SELECT USING (((deleted_at IS NULL) AND ((user_id = public.current_user_uuid()) OR public.is_admin())));


--
-- Name: payout_accounts payout_accounts_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payout_accounts_update ON public.payout_accounts FOR UPDATE USING (((user_id = public.current_user_uuid()) OR public.is_admin())) WITH CHECK (((user_id = public.current_user_uuid()) OR public.is_admin()));


--
-- Name: payouts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payouts ENABLE ROW LEVEL SECURITY;

--
-- Name: payouts payouts_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payouts_insert ON public.payouts FOR INSERT WITH CHECK (((user_id = public.current_user_uuid()) OR public.is_admin()));


--
-- Name: payouts payouts_update_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payouts_update_admin ON public.payouts FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: platform_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.platform_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: platform_settings platform_settings_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY platform_settings_all ON public.platform_settings USING ((public.is_admin() AND (organization_id = public.current_organization_uuid()))) WITH CHECK ((public.is_admin() AND (organization_id = public.current_organization_uuid())));


--
-- Name: properties; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.properties ENABLE ROW LEVEL SECURITY;

--
-- Name: properties properties_marketplace_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY properties_marketplace_select ON public.properties FOR SELECT USING (((deleted_at IS NULL) AND (EXISTS ( SELECT 1
   FROM public.property_listings l
  WHERE ((l.property_id = properties.id) AND (l.deleted_at IS NULL) AND (l.status = 'active'::public.listing_status) AND (l.is_public = true))))));


--
-- Name: properties properties_org_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY properties_org_delete ON public.properties FOR DELETE USING ((organization_id = public.current_organization_uuid()));


--
-- Name: properties properties_org_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY properties_org_insert ON public.properties FOR INSERT WITH CHECK ((organization_id = public.current_organization_uuid()));


--
-- Name: properties properties_org_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY properties_org_select ON public.properties FOR SELECT USING (((deleted_at IS NULL) AND ((organization_id = public.current_organization_uuid()) OR public.is_admin() OR (owner_id = public.current_user_uuid()) OR (default_agent_id = public.current_user_uuid()))));


--
-- Name: properties properties_org_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY properties_org_update ON public.properties FOR UPDATE USING ((organization_id = public.current_organization_uuid())) WITH CHECK ((organization_id = public.current_organization_uuid()));


--
-- Name: property_listings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.property_listings ENABLE ROW LEVEL SECURITY;

--
-- Name: property_media; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.property_media ENABLE ROW LEVEL SECURITY;

--
-- Name: property_media property_media_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY property_media_delete ON public.property_media FOR DELETE USING ((public.is_admin() OR public.is_property_owner_or_default_agent(property_id)));


--
-- Name: property_media property_media_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY property_media_insert ON public.property_media FOR INSERT WITH CHECK ((public.is_admin() OR public.is_property_owner_or_default_agent(property_id)));


--
-- Name: property_media property_media_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY property_media_select ON public.property_media FOR SELECT USING (((deleted_at IS NULL) AND (public.is_admin() OR (organization_id = public.current_organization_uuid()) OR (EXISTS ( SELECT 1
   FROM public.property_listings l
  WHERE ((l.property_id = property_media.property_id) AND (l.deleted_at IS NULL) AND (l.status = 'active'::public.listing_status) AND (l.is_public = true)))))));


--
-- Name: property_media property_media_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY property_media_update ON public.property_media FOR UPDATE USING ((public.is_admin() OR public.is_property_owner_or_default_agent(property_id))) WITH CHECK ((public.is_admin() OR public.is_property_owner_or_default_agent(property_id)));


--
-- Name: property_sale_details; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.property_sale_details ENABLE ROW LEVEL SECURITY;

--
-- Name: property_sale_details property_sale_details_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY property_sale_details_delete ON public.property_sale_details FOR DELETE USING ((public.is_admin() OR public.is_property_owner_or_default_agent(property_id)));


--
-- Name: property_sale_details property_sale_details_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY property_sale_details_insert ON public.property_sale_details FOR INSERT WITH CHECK ((public.is_admin() OR public.is_property_owner_or_default_agent(property_id)));


--
-- Name: property_sale_details property_sale_details_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY property_sale_details_select ON public.property_sale_details FOR SELECT USING ((public.is_admin() OR public.is_property_owner_or_default_agent(property_id) OR (EXISTS ( SELECT 1
   FROM public.property_listings l
  WHERE ((l.property_id = property_sale_details.property_id) AND (l.deleted_at IS NULL) AND (l.status = 'active'::public.listing_status) AND (l.is_public = true))))));


--
-- Name: property_sale_details property_sale_details_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY property_sale_details_update ON public.property_sale_details FOR UPDATE USING ((public.is_admin() OR public.is_property_owner_or_default_agent(property_id))) WITH CHECK ((public.is_admin() OR public.is_property_owner_or_default_agent(property_id)));


--
-- Name: property_sale_disclosures; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.property_sale_disclosures ENABLE ROW LEVEL SECURITY;

--
-- Name: property_viewings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.property_viewings ENABLE ROW LEVEL SECURITY;

--
-- Name: property_viewings property_viewings_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY property_viewings_delete_policy ON public.property_viewings FOR DELETE USING (((tenant_id = public.current_user_uuid()) OR public.is_admin()));


--
-- Name: property_viewings property_viewings_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY property_viewings_insert_policy ON public.property_viewings FOR INSERT WITH CHECK (((tenant_id = public.current_user_uuid()) OR public.is_listing_participant(listing_id) OR public.is_admin()));


--
-- Name: property_viewings property_viewings_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY property_viewings_select_policy ON public.property_viewings FOR SELECT USING (((tenant_id = public.current_user_uuid()) OR public.is_listing_participant(listing_id) OR public.is_admin()));


--
-- Name: property_viewings property_viewings_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY property_viewings_update_policy ON public.property_viewings FOR UPDATE USING (((tenant_id = public.current_user_uuid()) OR public.is_listing_participant(listing_id) OR public.is_admin())) WITH CHECK (((tenant_id = public.current_user_uuid()) OR public.is_listing_participant(listing_id) OR public.is_admin()));


--
-- Name: rent_invoices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rent_invoices ENABLE ROW LEVEL SECURITY;

--
-- Name: rent_invoices rent_invoices_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rent_invoices_delete ON public.rent_invoices FOR DELETE USING ((public.is_admin() AND (organization_id = public.current_organization_uuid())));


--
-- Name: rent_invoices rent_invoices_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rent_invoices_insert ON public.rent_invoices FOR INSERT WITH CHECK (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR public.is_property_owner_or_default_agent(property_id))));


--
-- Name: rent_invoices rent_invoices_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rent_invoices_select ON public.rent_invoices FOR SELECT USING (((deleted_at IS NULL) AND (organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (tenant_id = public.current_user_uuid()) OR public.is_property_owner_or_default_agent(property_id))));


--
-- Name: rent_invoices rent_invoices_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rent_invoices_update ON public.rent_invoices FOR UPDATE USING (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR public.is_property_owner_or_default_agent(property_id)))) WITH CHECK (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR public.is_property_owner_or_default_agent(property_id))));


--
-- Name: rental_applications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rental_applications ENABLE ROW LEVEL SECURITY;

--
-- Name: rental_applications rental_applications_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rental_applications_delete_policy ON public.rental_applications FOR DELETE USING (((applicant_id = public.current_user_uuid()) OR public.is_admin()));


--
-- Name: rental_applications rental_applications_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rental_applications_insert_policy ON public.rental_applications FOR INSERT WITH CHECK (((applicant_id = public.current_user_uuid()) OR public.is_admin()));


--
-- Name: rental_applications rental_applications_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rental_applications_select_policy ON public.rental_applications FOR SELECT USING (((applicant_id = public.current_user_uuid()) OR public.is_listing_participant(listing_id) OR public.is_admin()));


--
-- Name: rental_applications rental_applications_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rental_applications_update_policy ON public.rental_applications FOR UPDATE USING (((applicant_id = public.current_user_uuid()) OR public.is_listing_participant(listing_id) OR public.is_admin())) WITH CHECK (((applicant_id = public.current_user_uuid()) OR public.is_listing_participant(listing_id) OR public.is_admin()));


--
-- Name: property_sale_disclosures sale_disclosures_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sale_disclosures_delete ON public.property_sale_disclosures FOR DELETE USING ((public.is_admin() OR public.is_property_owner_or_default_agent(property_id)));


--
-- Name: property_sale_disclosures sale_disclosures_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sale_disclosures_insert ON public.property_sale_disclosures FOR INSERT WITH CHECK ((public.is_admin() OR public.is_property_owner_or_default_agent(property_id)));


--
-- Name: property_sale_disclosures sale_disclosures_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sale_disclosures_select ON public.property_sale_disclosures FOR SELECT USING ((public.is_admin() OR public.is_property_owner_or_default_agent(property_id) OR (EXISTS ( SELECT 1
   FROM public.property_listings l
  WHERE ((l.property_id = property_sale_disclosures.property_id) AND (l.deleted_at IS NULL) AND (l.status = 'active'::public.listing_status) AND (l.is_public = true))))));


--
-- Name: property_sale_disclosures sale_disclosures_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sale_disclosures_update ON public.property_sale_disclosures FOR UPDATE USING ((public.is_admin() OR public.is_property_owner_or_default_agent(property_id))) WITH CHECK ((public.is_admin() OR public.is_property_owner_or_default_agent(property_id)));


--
-- Name: saved_listings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.saved_listings ENABLE ROW LEVEL SECURITY;

--
-- Name: saved_listings saved_listings_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY saved_listings_delete ON public.saved_listings FOR DELETE USING ((public.is_admin() AND (organization_id = public.current_organization_uuid())));


--
-- Name: saved_listings saved_listings_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY saved_listings_insert ON public.saved_listings FOR INSERT WITH CHECK (((organization_id = public.current_organization_uuid()) AND (user_id = public.current_user_uuid())));


--
-- Name: saved_listings saved_listings_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY saved_listings_select ON public.saved_listings FOR SELECT USING (((deleted_at IS NULL) AND (organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (user_id = public.current_user_uuid()))));


--
-- Name: saved_listings saved_listings_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY saved_listings_update ON public.saved_listings FOR UPDATE USING (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (user_id = public.current_user_uuid())))) WITH CHECK (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR (user_id = public.current_user_uuid()))));


--
-- Name: sms_templates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sms_templates ENABLE ROW LEVEL SECURITY;

--
-- Name: sms_templates sms_templates_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sms_templates_all ON public.sms_templates USING ((public.is_admin() AND (organization_id = public.current_organization_uuid()))) WITH CHECK ((public.is_admin() AND (organization_id = public.current_organization_uuid())));


--
-- Name: support_tickets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

--
-- Name: support_tickets support_tickets_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY support_tickets_delete_policy ON public.support_tickets FOR DELETE USING (((user_id = public.current_user_uuid()) OR public.is_admin()));


--
-- Name: support_tickets support_tickets_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY support_tickets_insert_policy ON public.support_tickets FOR INSERT WITH CHECK (((user_id = public.current_user_uuid()) OR public.is_admin()));


--
-- Name: support_tickets support_tickets_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY support_tickets_select_policy ON public.support_tickets FOR SELECT USING (((user_id = public.current_user_uuid()) OR (assigned_to = public.current_user_uuid()) OR public.is_admin()));


--
-- Name: support_tickets support_tickets_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY support_tickets_update_policy ON public.support_tickets FOR UPDATE USING (((user_id = public.current_user_uuid()) OR (assigned_to = public.current_user_uuid()) OR public.is_admin())) WITH CHECK (((user_id = public.current_user_uuid()) OR (assigned_to = public.current_user_uuid()) OR public.is_admin()));


--
-- Name: tenancies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tenancies ENABLE ROW LEVEL SECURITY;

--
-- Name: tenancies tenancies_delete_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenancies_delete_policy ON public.tenancies FOR DELETE USING (((deleted_at IS NULL) AND (public.is_property_owner_or_default_agent(property_id) OR public.is_admin())));


--
-- Name: tenancies tenancies_insert_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenancies_insert_policy ON public.tenancies FOR INSERT WITH CHECK ((public.is_admin() OR public.is_property_owner_or_default_agent(property_id)));


--
-- Name: tenancies tenancies_select_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenancies_select_policy ON public.tenancies FOR SELECT USING (((deleted_at IS NULL) AND ((tenant_id = public.current_user_uuid()) OR public.is_property_owner_or_default_agent(property_id) OR public.is_admin())));


--
-- Name: tenancies tenancies_update_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenancies_update_policy ON public.tenancies FOR UPDATE USING (((deleted_at IS NULL) AND ((tenant_id = public.current_user_uuid()) OR public.is_property_owner_or_default_agent(property_id) OR public.is_admin()))) WITH CHECK (((tenant_id = public.current_user_uuid()) OR public.is_property_owner_or_default_agent(property_id) OR public.is_admin()));


--
-- Name: wallet_accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.wallet_accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: wallet_accounts wallet_accounts_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wallet_accounts_delete ON public.wallet_accounts FOR DELETE USING ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name)));


--
-- Name: wallet_accounts wallet_accounts_delete_admin_or_service; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wallet_accounts_delete_admin_or_service ON public.wallet_accounts FOR DELETE USING ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name)));


--
-- Name: wallet_accounts wallet_accounts_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wallet_accounts_insert ON public.wallet_accounts FOR INSERT WITH CHECK ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name)));


--
-- Name: wallet_accounts wallet_accounts_insert_admin_or_service; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wallet_accounts_insert_admin_or_service ON public.wallet_accounts FOR INSERT WITH CHECK ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name)));


--
-- Name: wallet_accounts wallet_accounts_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wallet_accounts_select ON public.wallet_accounts FOR SELECT USING (((organization_id = public.current_organization_uuid()) AND (public.is_admin() OR ((user_id = public.current_user_uuid()) AND (is_platform_wallet = false)))));


--
-- Name: wallet_accounts wallet_accounts_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wallet_accounts_update ON public.wallet_accounts FOR UPDATE USING ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name))) WITH CHECK ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name)));


--
-- Name: wallet_accounts wallet_accounts_update_admin_or_service; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wallet_accounts_update_admin_or_service ON public.wallet_accounts FOR UPDATE USING ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name))) WITH CHECK ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name)));


--
-- Name: wallet_transactions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;

--
-- Name: wallet_transactions wallet_tx_delete_admin_or_service; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wallet_tx_delete_admin_or_service ON public.wallet_transactions FOR DELETE USING ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name)));


--
-- Name: wallet_transactions wallet_tx_insert_admin_or_service; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wallet_tx_insert_admin_or_service ON public.wallet_transactions FOR INSERT WITH CHECK ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name)));


--
-- Name: wallet_transactions wallet_tx_modify_admin_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wallet_tx_modify_admin_delete ON public.wallet_transactions FOR DELETE USING ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name)));


--
-- Name: wallet_transactions wallet_tx_modify_admin_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wallet_tx_modify_admin_insert ON public.wallet_transactions FOR INSERT WITH CHECK ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name)));


--
-- Name: wallet_transactions wallet_tx_modify_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wallet_tx_modify_admin_update ON public.wallet_transactions FOR UPDATE USING ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name))) WITH CHECK ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name)));


--
-- Name: wallet_transactions wallet_tx_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wallet_tx_select ON public.wallet_transactions FOR SELECT USING (((organization_id = public.current_organization_uuid()) AND (EXISTS ( SELECT 1
   FROM public.wallet_accounts wa
  WHERE ((wa.id = wallet_transactions.wallet_account_id) AND (public.is_admin() OR ((wa.user_id = public.current_user_uuid()) AND (wa.is_platform_wallet = false))))))));


--
-- Name: wallet_transactions wallet_tx_update_admin_or_service; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wallet_tx_update_admin_or_service ON public.wallet_transactions FOR UPDATE USING ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name))) WITH CHECK ((public.is_admin() OR (CURRENT_USER = 'rentease_service'::name)));


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO rentease_app;
GRANT ALL ON SCHEMA public TO rentease_service;


--
-- Name: FUNCTION ensure_wallet_account(p_org uuid, p_user uuid, p_currency character varying, p_is_platform boolean); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.ensure_wallet_account(p_org uuid, p_user uuid, p_currency character varying, p_is_platform boolean) TO rentease_service;


--
-- Name: FUNCTION generate_payment_splits(p_payment_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.generate_payment_splits(p_payment_id uuid) TO rentease_service;


--
-- Name: FUNCTION generate_receipt(payment_uuid uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.generate_receipt(payment_uuid uuid) TO rentease_service;


--
-- Name: FUNCTION payments_success_trigger_fn(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.payments_success_trigger_fn() TO rentease_service;


--
-- Name: FUNCTION wallet_credit_from_splits(p_payment_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.wallet_credit_from_splits(p_payment_id uuid) TO rentease_service;


--
-- Name: TABLE api_keys; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.api_keys TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.api_keys TO rentease_service;


--
-- Name: TABLE audit_logs; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.audit_logs TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.audit_logs TO rentease_service;


--
-- Name: TABLE audit_logs_default; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.audit_logs_default TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.audit_logs_default TO rentease_service;


--
-- Name: TABLE contract_parties; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.contract_parties TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.contract_parties TO rentease_service;


--
-- Name: TABLE contract_signatures; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.contract_signatures TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.contract_signatures TO rentease_service;


--
-- Name: TABLE contractors; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.contractors TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.contractors TO rentease_service;


--
-- Name: TABLE contracts; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.contracts TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.contracts TO rentease_service;


--
-- Name: TABLE conversation_participants; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.conversation_participants TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.conversation_participants TO rentease_service;


--
-- Name: TABLE conversations; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.conversations TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.conversations TO rentease_service;


--
-- Name: TABLE customer_payment_methods; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.customer_payment_methods TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.customer_payment_methods TO rentease_service;


--
-- Name: TABLE dispute_messages; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.dispute_messages TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.dispute_messages TO rentease_service;


--
-- Name: TABLE disputes; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.disputes TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.disputes TO rentease_service;


--
-- Name: TABLE documents; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.documents TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.documents TO rentease_service;


--
-- Name: TABLE email_templates; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.email_templates TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.email_templates TO rentease_service;


--
-- Name: TABLE invoice_payments; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.invoice_payments TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.invoice_payments TO rentease_service;


--
-- Name: TABLE lead_activities; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.lead_activities TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.lead_activities TO rentease_service;


--
-- Name: TABLE leads; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.leads TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.leads TO rentease_service;


--
-- Name: TABLE maintenance_attachments; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.maintenance_attachments TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.maintenance_attachments TO rentease_service;


--
-- Name: TABLE maintenance_requests; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.maintenance_requests TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.maintenance_requests TO rentease_service;


--
-- Name: TABLE maintenance_updates; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.maintenance_updates TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.maintenance_updates TO rentease_service;


--
-- Name: TABLE properties; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.properties TO rentease_app;


--
-- Name: TABLE property_listings; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.property_listings TO rentease_app;


--
-- Name: TABLE marketplace_listings; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.marketplace_listings TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.marketplace_listings TO rentease_service;


--
-- Name: TABLE message_attachments; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.message_attachments TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.message_attachments TO rentease_service;


--
-- Name: TABLE messages; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.messages TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.messages TO rentease_service;


--
-- Name: TABLE notifications; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.notifications TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.notifications TO rentease_service;


--
-- Name: SEQUENCE org_1f297ca1_2764_4541_9d2e_00fe49e3d3bc_receipt_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.org_1f297ca1_2764_4541_9d2e_00fe49e3d3bc_receipt_seq TO rentease_app;


--
-- Name: TABLE organizations; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.organizations TO rentease_app;


--
-- Name: TABLE payment_splits; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.payment_splits TO rentease_app;


--
-- Name: TABLE payments; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.payments TO rentease_app;


--
-- Name: TABLE payout_accounts; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.payout_accounts TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.payout_accounts TO rentease_service;


--
-- Name: TABLE payouts; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.payouts TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.payouts TO rentease_service;


--
-- Name: TABLE pg_stat_statements; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.pg_stat_statements TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.pg_stat_statements TO rentease_service;


--
-- Name: TABLE pg_stat_statements_info; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.pg_stat_statements_info TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.pg_stat_statements_info TO rentease_service;


--
-- Name: TABLE platform_settings; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.platform_settings TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.platform_settings TO rentease_service;


--
-- Name: TABLE property_media; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.property_media TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.property_media TO rentease_service;


--
-- Name: TABLE property_sale_details; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.property_sale_details TO rentease_app;


--
-- Name: TABLE property_sale_disclosures; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.property_sale_disclosures TO rentease_app;


--
-- Name: TABLE property_viewings; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.property_viewings TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.property_viewings TO rentease_service;


--
-- Name: SEQUENCE rentease_invoice_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.rentease_invoice_seq TO rentease_app;
GRANT SELECT,USAGE ON SEQUENCE public.rentease_invoice_seq TO rentease_service;


--
-- Name: TABLE rent_invoices; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.rent_invoices TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.rent_invoices TO rentease_service;


--
-- Name: TABLE rental_applications; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.rental_applications TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.rental_applications TO rentease_service;


--
-- Name: TABLE saved_listings; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.saved_listings TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.saved_listings TO rentease_service;


--
-- Name: TABLE sms_templates; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.sms_templates TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.sms_templates TO rentease_service;


--
-- Name: TABLE support_tickets; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.support_tickets TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.support_tickets TO rentease_service;


--
-- Name: TABLE tenancies; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.tenancies TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.tenancies TO rentease_service;


--
-- Name: TABLE users; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.users TO rentease_app;


--
-- Name: TABLE wallet_accounts; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.wallet_accounts TO rentease_app;


--
-- Name: TABLE wallet_transactions; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.wallet_transactions TO rentease_app;


--
-- Name: TABLE wallet_balances; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.wallet_balances TO rentease_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.wallet_balances TO rentease_service;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE mac IN SCHEMA public GRANT SELECT,USAGE ON SEQUENCES TO rentease_app;
ALTER DEFAULT PRIVILEGES FOR ROLE mac IN SCHEMA public GRANT SELECT,USAGE ON SEQUENCES TO rentease_service;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE rentease_service IN SCHEMA public GRANT SELECT,USAGE ON SEQUENCES TO rentease_service;
ALTER DEFAULT PRIVILEGES FOR ROLE rentease_service IN SCHEMA public GRANT SELECT,USAGE ON SEQUENCES TO rentease_app;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE mac IN SCHEMA public GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES TO rentease_app;
ALTER DEFAULT PRIVILEGES FOR ROLE mac IN SCHEMA public GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES TO rentease_service;


--
-- PostgreSQL database dump complete
--

\unrestrict cGnz1NP39pN0yIcDGeu1f49EoSMNrAHeuGZmkxhL1GXgKIHDPfCtzbey4rF1n10

