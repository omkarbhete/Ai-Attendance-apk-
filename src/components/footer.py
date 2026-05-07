# import streamlit as st


# def footer_home():
#     logo_url = "https://logos.textgiraffe.com/logos/logo-name/Rishi-designstyle-cartoon-m.png"
    
#     st.markdown(f"""
#         <div style="margin-top:2rem; display:flex; gap:6px; justify-content:center; items-align:center">
#         <p style="font-weight:bold; color:white;"> Created with ❤️ by </p>  
#         <img src='{logo_url}' style='max-height:50px' />
#         </div>
                
#                 """, unsafe_allow_html=True)


# def footer_dashboard():
#     logo_url = "https://logos.textgiraffe.com/logos/logo-name/Rishi-designstyle-cartoon-m.png"
    
#     st.markdown(f"""
#         <div style="margin-top:2rem; display:flex; gap:6px; justify-content:center; items-align:center">
#         <p style="font-weight:bold; color:black;"> Created with ❤️ by </p>  
#         <img src='{logo_url}' style='max-height:25px' />
#         </div>
                
#                 """, unsafe_allow_html=True)



import streamlit as st

def footer_home():
    logo_url = "https://logos.textgiraffe.com/logos/logo-name/Rishi-designstyle-cartoon-m.png"
    
    st.markdown(f"""
        <div style="margin-top: 3rem; padding-top: 1.5rem; display: flex; gap: 10px; justify-content: center; align-items: center; border-top: 1px solid rgba(255, 255, 255, 0.1);">
            <p style="font-family: system-ui, -apple-system, sans-serif; font-weight: 500; font-size: 15px; color: #ffffff; margin: 0; opacity: 0.9; letter-spacing: 0.5px;"> 
                Created with ❤️ by 
            </p>  
            <img src='{logo_url}' style='max-height: 45px; filter: drop-shadow(0 4px 8px rgba(0,0,0,0.3));' />
        </div>
    """, unsafe_allow_html=True)


def footer_dashboard():
    logo_url = "https://logos.textgiraffe.com/logos/logo-name/Rishi-designstyle-cartoon-m.png"
    
    st.markdown(f"""
        <div style="margin-top: 3rem; padding-top: 1rem; display: flex; gap: 8px; justify-content: center; align-items: center; border-top: 1px solid rgba(0, 0, 0, 0.08);">
            <p style="font-family: system-ui, -apple-system, sans-serif; font-weight: 600; font-size: 14px; color: #000000; margin: 0; opacity: 0.8; letter-spacing: 0.5px;"> 
                Created with ❤️ by 
            </p>  
            <img src='{logo_url}' style='max-height: 30px; filter: drop-shadow(0 2px 4px rgba(0,0,0,0.15));' />
        </div>
    """, unsafe_allow_html=True)