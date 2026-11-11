-- Migration: Create sales_invoices and invoice_items tables
-- Date: 2026-03-24
-- Purpose: Separate sales invoice management from sales orders

-- Create sales_invoices table (similar structure to sales_orders)
CREATE TABLE IF NOT EXISTS public.sales_invoices (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  invoice_number character varying(50) NOT NULL,
  salesman_id uuid NULL,
  customer_id uuid NULL,
  customer_name character varying(255) NULL DEFAULT 'Walk-in Customer'::character varying,
  invoice_date timestamp with time zone NOT NULL,
  total_amount numeric(10, 2) NOT NULL,
  gst_amount numeric(10, 2) NOT NULL,
  net_amount numeric(10, 2) NOT NULL,
  status character varying(50) NULL DEFAULT 'pending'::character varying,
  notes text NULL,
  synced_to_tally boolean NULL DEFAULT false,
  tally_sync_date timestamp with time zone NULL,
  created_at timestamp with time zone NULL DEFAULT now(),
  discount_amount numeric(10, 2) NULL DEFAULT 0,
  discount_percentage numeric(5, 2) NULL DEFAULT 0,
  subtotal_before_discount numeric(10, 2) NULL DEFAULT 0,
  items jsonb NULL DEFAULT '[]'::jsonb,
  updated_at timestamp with time zone NULL,
  customer_category_id uuid NULL,
  company_id uuid NULL,
  company_name text NULL,
  "Guid" text NULL,
  customer_category_name text NULL,
  "Type" text NULL DEFAULT 'Credit'::text,
  edit_request_status text NOT NULL DEFAULT 'none'::text,
  can_edit_until timestamp with time zone NULL,
  edit_requested_at timestamp with time zone NULL,
  edit_approved_at timestamp with time zone NULL,
  edit_rejected_at timestamp with time zone NULL,
  shipping_address text NULL,
  invoice_latitude numeric NULL,
  invoice_longitude numeric NULL,
  invoice_address text NULL,
  distance_from_customer numeric NULL,
  remarks text NULL,
  CONSTRAINT sales_invoices_pkey PRIMARY KEY (id)
) TABLESPACE pg_default;

-- Create indexes for sales_invoices
CREATE INDEX IF NOT EXISTS idx_sales_invoices_company_created_at 
  ON public.sales_invoices USING btree (company_id, created_at DESC) TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_sales_invoices_invoice_number 
  ON public.sales_invoices USING btree (invoice_number) TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_sales_invoices_customer_id 
  ON public.sales_invoices USING btree (customer_id) TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_sales_invoices_salesman_id 
  ON public.sales_invoices USING btree (salesman_id) TABLESPACE pg_default;

-- Create invoice_items table (similar structure to order_items)
CREATE TABLE IF NOT EXISTS public.invoice_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  invoice_id uuid NULL,
  product_id uuid NULL,
  product_name character varying(255) NOT NULL,
  product_code character varying(100) NULL,
  quantity integer NOT NULL,
  unit_price numeric(10, 2) NOT NULL,
  gst_rate numeric(5, 2) NOT NULL,
  gst_amount numeric(10, 2) NOT NULL,
  total_amount numeric(10, 2) NOT NULL,
  created_at timestamp with time zone NULL DEFAULT now(),
  discount_percentage numeric(5, 2) NULL DEFAULT 0,
  discount_amount numeric(10, 2) NULL DEFAULT 0,
  category_discount_percentage numeric(5, 2) NULL DEFAULT 0,
  item_group_id uuid NULL,
  customer_category_id uuid NULL,
  company_id uuid NULL,
  company_name text NULL,
  "Guid" text NULL,
  CONSTRAINT invoice_items_pkey PRIMARY KEY (id),
  CONSTRAINT invoice_items_invoice_id_fkey FOREIGN KEY (invoice_id) 
    REFERENCES sales_invoices (id) ON DELETE CASCADE
) TABLESPACE pg_default;

-- Create indexes for invoice_items
CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice_id 
  ON public.invoice_items USING btree (invoice_id) TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_invoice_items_product_id 
  ON public.invoice_items USING btree (product_id) TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_invoice_items_company_id 
  ON public.invoice_items USING btree (company_id) TABLESPACE pg_default;

-- Create trigger function to sync company fields (similar to order_items)
CREATE OR REPLACE FUNCTION sync_invoice_items_company_fields()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.company_id IS NOT NULL AND NEW."Guid" IS NULL THEN
    SELECT "Guid" INTO NEW."Guid"
    FROM tally_companies
    WHERE id = NEW.company_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for invoice_items
DROP TRIGGER IF EXISTS trg_sync_invoice_items_company_fields ON invoice_items;
CREATE TRIGGER trg_sync_invoice_items_company_fields
  BEFORE INSERT OR UPDATE OF company_id, "Guid"
  ON invoice_items
  FOR EACH ROW
  EXECUTE FUNCTION sync_invoice_items_company_fields();
