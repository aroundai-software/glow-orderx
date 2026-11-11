-- Migration: Add foreign key constraint for customer_category_id
-- Date: 2026-06-24
-- Purpose: Enable Supabase joins between customers and customer_categories tables

-- Add foreign key constraint from customers.customer_category_id to customer_categories.id
ALTER TABLE public.customers 
ADD CONSTRAINT customers_customer_category_id_fkey 
FOREIGN KEY (customer_category_id) 
REFERENCES public.customer_categories(id) 
ON DELETE SET NULL 
ON UPDATE CASCADE;
