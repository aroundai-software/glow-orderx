-- Change ItemQuantity from integer to numeric to store decimal quantities (e.g. 22.50 MTR)
ALTER TABLE public.products
ALTER COLUMN "ItemQuantity" TYPE numeric USING "ItemQuantity"::numeric;
