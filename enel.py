from playwright.sync_api import sync_playwright
import re
from typing import Optional, List


class EnelScraper:
    def __init__(self, headless: bool = False):
        self.playwright = sync_playwright().start()
        self.browser = self.playwright.chromium.launch(headless=headless)
        self.context = self.browser.new_context()
        self.page = self.context.new_page()
        self.timeout = 15000


    def login(self, email: str, password: str) -> bool:
        """Realiza o login no site da Enel"""
        try:
            self.page.goto("https://www.enel.com.br/pt-saopaulo/login.html")
            self.page.wait_for_url(
                "https://www.enel.com.br/pt-saopaulo/login.html?commonAuthCallerPath=%2Fsamlsso*",
                timeout=self.timeout
            )

            self.page.fill('[id="email"]', email)
            self.page.fill('[id="password"]', password)
            self.page.click('[alt="acessar"]')

            self.page.wait_for_url(
                re.compile(r"https://www\.enel\.com\.br/.*/private-area/home\.html"),
                timeout=self.timeout
            )
            return True
        
        except Exception as e:
            print(f"Erro durante login: {e}")
            return False
        

    def navigate_to_bills(self) -> bool:
        """Navega até a seção de contas"""
        try:
            print('Aguardando seletor "ver contas"')
            ver_contas = self.page.locator('[title="ver contas"]').first
            ver_contas.wait_for(state='attached')
            self.page.evaluate('''() => { document.querySelector('[title="ver contas"]').click(); }''')
            
            botao_all_contas = self.page.locator('app-enel-button').nth(1)
            botao_all_contas.wait_for(state='visible')
            botao_all_contas.click()
            return True
        
        except Exception as e:
            print(f"Erro ao navegar para contas: {e}")
            return False


    def get_bills_data(self) -> Optional[dict]:
        """Obtém dados das contas para pagar"""
        try:
            self.page.locator('[style*="border-color: rgb(255, 90, 15)"]').first.wait_for()
            contas_para_pagar = self.page.locator('[style*="border-color: rgb(255, 90, 15)"]').all()
            
            if not contas_para_pagar:
                print("Nenhuma conta encontrada")
                return None

            contas_para_pagar[0].click()

            vencimento_status = self._get_element_text(
                '[class="bottom-space-4 enel-card instalation installation-card"]'
            )
            
            codigo_boleto = self._get_element_text('[id="payCode"]')
            
            codigo_pix = self._get_element_text('[id="pixCode"]')

            return {
                'status': vencimento_status.split('\n')[1],
                'status': vencimento_status.split('\n')[3],
                'codigo_boleto': codigo_boleto,
                'codigo_pix': codigo_pix
            }
            
        except Exception as e:
            print(f"Erro ao obter dados das contas: {e}")
            return None


    def _get_element_text(self, selector: str) -> Optional[str]:
        """Método auxiliar para obter texto de um elemento"""
        try:
            self.page.locator(selector).first.wait_for()
            return self.page.evaluate(f'''() => {{
                const el = document.querySelector('{selector}');
                return el ? el.innerText.trim() : null;
            }}''')
            
        except Exception:
            return None


    def run(self, email: str, password: str):
        """Executa o fluxo completo"""
        if not self.login(email, password):
            return

        if not self.navigate_to_bills():
            return

        bills_data = self.get_bills_data()
        if bills_data:
            print("Dados obtidos:\n")
            print(bills_data)
            return bills_data

        input("Pressione Enter para fechar o navegador...")
        self.close()


    def close(self):
        """Fecha os recursos"""
        self.context.close()
        self.browser.close()
        self.playwright.stop()


if __name__ == "__main__":
    scraper = EnelScraper(headless=False)
    scraper.run(
        email="teste@yahoo.com.br",
        password="senhaTeste"
    )
