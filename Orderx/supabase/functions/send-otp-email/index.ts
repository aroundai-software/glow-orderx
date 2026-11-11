import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

interface EmailRequest {
  email: string
  otp: string
  type: 'registration' | 'password_reset'
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { email, otp, type }: EmailRequest = await req.json()

    console.log(`📧 Sending ${type} OTP to: ${email}`)

    // Validate input
    if (!email || !otp || !type) {
      throw new Error('Missing required parameters: email, otp, or type')
    }

    // Get Resend API key from environment
    const resendApiKey = Deno.env.get('RESEND_API_KEY')
    
    // Prepare email content
    const subject = type === 'registration' 
      ? 'Verify Your Email - Orderx'
      : 'Reset Your Password - Orderx'

    const htmlContent = `
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <style>
            body { font-family: Arial, sans-serif; background-color: #f5f5f5; }
            .container { max-width: 600px; margin: 0 auto; background-color: white; padding: 20px; border-radius: 8px; }
            .header { color: #1976D2; font-size: 24px; font-weight: bold; margin-bottom: 20px; }
            .content { color: #333; line-height: 1.6; }
            .otp-box { background-color: #f0f4ff; border-left: 4px solid #1976D2; padding: 15px; margin: 20px 0; }
            .otp-code { font-size: 32px; font-weight: bold; color: #1976D2; letter-spacing: 2px; }
            .footer { color: #666; font-size: 12px; margin-top: 20px; border-top: 1px solid #eee; padding-top: 10px; }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              ${type === 'registration' ? '✉️ Email Verification' : '🔐 Password Reset'}
            </div>
            <div class="content">
              <p>Hello,</p>
              <p>${type === 'registration' 
                ? 'Thank you for registering with Orderx. Please verify your email address using the code below:'
                : 'We received a request to reset your password. Use the code below to proceed:'
              }</p>
              
              <div class="otp-box">
                <p style="margin: 0; color: #666; font-size: 14px;">Your verification code:</p>
                <div class="otp-code">${otp}</div>
              </div>
              
              <p style="color: #666; font-size: 14px;">
                This code will expire in <strong>10 minutes</strong>. If you didn't request this code, please ignore this email.
              </p>
              
              <p>Best regards,<br><strong>Orderx Team</strong></p>
            </div>
            <div class="footer">
              <p>This is an automated email. Please do not reply to this message.</p>
              <p>&copy; 2025 Orderx. All rights reserved.</p>
            </div>
          </div>
        </body>
      </html>
    `

    // If Resend API key is configured, try to send via Resend
    if (resendApiKey) {
      try {
        const resendResponse = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${resendApiKey}`,
          },
          body: JSON.stringify({
            from: 'onboarding@resend.dev',
            to: email,
            subject: subject,
            html: htmlContent,
          }),
        })

        const resendData = await resendResponse.json()

        if (resendResponse.ok) {
          console.log('✅ Email sent successfully via Resend:', resendData.id)
          return new Response(
            JSON.stringify({ 
              success: true,
              message: 'Email sent successfully',
              emailId: resendData.id
            }),
            { 
              headers: { ...corsHeaders, 'Content-Type': 'application/json' },
              status: 200 
            },
          )
        } else {
          console.warn('⚠️ Resend API error:', resendData)
        }
      } catch (resendError) {
        console.warn('⚠️ Resend API failed:', resendError)
      }
    }

    // Fallback: Store in email_queue table
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    if (supabaseUrl && supabaseKey) {
      const supabase = createClient(supabaseUrl, supabaseKey)
      
      const { error } = await supabase.from('email_queue').insert({
        recipient_email: email,
        subject: subject,
        body: htmlContent,
        otp_code: otp,
        email_type: type,
        status: 'pending',
        attempts: 0,
      })

      if (error) {
        console.warn('⚠️ Failed to queue email:', error)
      } else {
        console.log('✅ Email queued in database for later processing')
        return new Response(
          JSON.stringify({ 
            success: true,
            message: 'Email queued for sending',
            queued: true
          }),
          { 
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200 
          },
        )
      }
    }

    // If all else fails, return success with OTP (for testing)
    console.warn('⚠️ Email service not fully configured, returning OTP for testing')
    return new Response(
      JSON.stringify({ 
        success: true,
        message: 'OTP generated (email service not configured)',
        otp: otp
      }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200 
      },
    )

  } catch (error) {
    console.error('❌ Error in send-otp-email function:', error)
    
    return new Response(
      JSON.stringify({ 
        success: false,
        error: error.message || 'Failed to send email'
      }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500 
      },
    )
  }
})
