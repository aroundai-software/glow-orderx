-- Stock Notifications Table
-- This table stores notifications sent by salesmen to admin about low stock or out-of-stock items

CREATE TABLE IF NOT EXISTS stock_notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    product_name TEXT NOT NULL,
    product_code TEXT,
    stock_level INTEGER NOT NULL,
    notification_type TEXT NOT NULL CHECK (notification_type IN ('low_stock', 'out_of_stock')),
    salesman_id UUID NOT NULL REFERENCES salesman(id) ON DELETE CASCADE,
    salesman_name TEXT NOT NULL,
    notes TEXT,
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_stock_notifications_product_id ON stock_notifications(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_notifications_salesman_id ON stock_notifications(salesman_id);
CREATE INDEX IF NOT EXISTS idx_stock_notifications_is_read ON stock_notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_stock_notifications_created_at ON stock_notifications(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_notifications_type ON stock_notifications(notification_type);

-- Enable Row Level Security
ALTER TABLE stock_notifications ENABLE ROW LEVEL SECURITY;

-- Policy: Salesmen can insert their own notifications
CREATE POLICY "Salesmen can insert their own notifications"
ON stock_notifications
FOR INSERT
TO authenticated
WITH CHECK (
    auth.uid() = salesman_id
);

-- Policy: Salesmen can view their own notifications
CREATE POLICY "Salesmen can view their own notifications"
ON stock_notifications
FOR SELECT
TO authenticated
USING (
    auth.uid() = salesman_id
);

-- Policy: Admins can view all notifications
CREATE POLICY "Admins can view all notifications"
ON stock_notifications
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM admin
        WHERE admin.id = auth.uid()
    )
);

-- Policy: Admins can update notifications (mark as read)
CREATE POLICY "Admins can update notifications"
ON stock_notifications
FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM admin
        WHERE admin.id = auth.uid()
    )
);

-- Policy: Admins can delete notifications
CREATE POLICY "Admins can delete notifications"
ON stock_notifications
FOR DELETE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM admin
        WHERE admin.id = auth.uid()
    )
);

-- Add comments for documentation
COMMENT ON TABLE stock_notifications IS 'Stores stock alert notifications sent by salesmen to admin';
COMMENT ON COLUMN stock_notifications.notification_type IS 'Type of notification: low_stock (stock <= 10) or out_of_stock (stock = 0)';
COMMENT ON COLUMN stock_notifications.is_read IS 'Whether the admin has read this notification';
COMMENT ON COLUMN stock_notifications.read_at IS 'Timestamp when the notification was marked as read';
