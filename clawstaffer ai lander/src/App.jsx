import { useState, useEffect, useRef } from 'react'
import { getCalApi } from "@calcom/embed-react"
import './App.css'

function App() {
  const calRef = useRef(null);

  useEffect(() => {
    (async function () {
      const cal = await getCalApi({"namespace":"30min"});
      calRef.current = cal;
      cal("floatingButton", {"calLink":"clawstaffer/30min","config":{"layout":"month_view","useSlotsViewOnSmallScreen":"true"},"buttonColor":"#ff8727","buttonText":"Get a Demo"});
      cal("ui", {"hideEventTypeDetails":false,"layout":"month_view"});
    })();
  }, []);

  const openCalPopup = () => {
    if (calRef.current) {
      calRef.current("modal", {
        calLink: "clawstaffer/30min",
        config: { layout: "month_view" }
      });
    }
  };

  const trustedBy = [
    { name: 'Global Bank', glyph: 'G' },
    { name: 'Fortune Tech', glyph: 'T' },
    { name: 'Prime Manufacturing', glyph: 'M' },
    { name: 'Health Enterprise', glyph: 'H' },
    { name: 'Logistics Giant', glyph: 'L' },
  ]

  return (
    <>
      <a className="skipLink" href="#main">
        Skip to content
      </a>

      <header className="siteHeader">
        <div className="container headerInner">
          <a className="brand" href="/" aria-label="ClawStaffer home">
            <img className="brandLogo" src="/logo.png" alt="ClawStaffer logo" />
            <span className="brandText">ClawStaffer</span>
          </a>

          <nav className="nav" aria-label="Primary">
            <a className="navLink" href="#security">
              Security &amp; Compliance
            </a>
            <a className="navLink" href="#results">
              Results
            </a>
            <a className="navLink" href="#demo">
              Contact Sales
            </a>
          </nav>

          <button className="navCta" onClick={openCalPopup}>
            Request Demo
          </button>
        </div>
      </header>

      <main id="main">
        <section className="hero">
          <div className="container heroInner">
            <div className="heroCopy">
              <p className="eyebrow">Autonomous AI workforce for enterprises</p>
              <h1 className="heroTitle">Deploy Unlimited AI Agents That Work 24/7</h1>
              <p className="heroSubtitle">
                Replace repetitive roles, eliminate downtime, and scale operations without headcount constraints. Fully autonomous agents that evaluate scenarios, make decisions, and execute workflows end-to-end with enterprise guardrails—delivering measurable ROI from day one.
              </p>

              <div className="heroCtas" role="group" aria-label="Hero call to action">
                <button className="button buttonPrimary" onClick={openCalPopup}>
                  Get Enterprise Demo <span aria-hidden="true">→</span>
                </button>
              </div>

              <div className="trustedBy" aria-label="Trusted by">
                <p className="trustedLabel">Trusted by</p>
                <div className="trustedGrid">
                  {trustedBy.map((logo) => (
                    <div className="trustedLogo" key={logo.name} aria-label={logo.name}>
                      <span className="trustedGlyph" aria-hidden="true">
                        {logo.glyph}
                      </span>
                      <span className="trustedName">{logo.name}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>

            <div className="heroPanel" aria-label="Product highlights">
              <div className="heroPanelTop">
                <div className="badgeRow" id="security">
                  <span className="badge">SOC 2 Type II</span>
                  <span className="badge">GDPR</span>
                  <span className="badge">Audit Trails</span>
                  <span className="badge">Custom VPC</span>
                  <span className="badge">Scenario Decisioning</span>
                </div>
              </div>
              <div className="heroPanelBody">
                <div className="mockHeader">
                  <div className="mockDots" aria-hidden="true">
                    <span />
                    <span />
                    <span />
                  </div>
                  <div className="mockTitle">Agent Fleet Overview</div>
                </div>
                <div className="mockGrid" aria-hidden="true">
                  <div className="mockCard">
                    <div className="mockKpiLabel">Active agents</div>
                    <div className="mockKpiValue">128</div>
                  </div>
                  <div className="mockCard">
                    <div className="mockKpiLabel">Uptime</div>
                    <div className="mockKpiValue">99.9%</div>
                  </div>
                  <div className="mockCard">
                    <div className="mockKpiLabel">Tasks today</div>
                    <div className="mockKpiValue">18,402</div>
                  </div>
                  <div className="mockCard">
                    <div className="mockKpiLabel">Cost savings</div>
                    <div className="mockKpiValue">$2.4M</div>
                  </div>
                </div>
                <div className="mockTimeline" aria-hidden="true">
                  <div className="mockTimelineTitle">Completion rate</div>
                  <div className="mockBars">
                    <span style={{ width: '86%' }} />
                    <span style={{ width: '92%' }} />
                    <span style={{ width: '78%' }} />
                    <span style={{ width: '96%' }} />
                  </div>
                </div>
              </div>
              <div className="heroPanelBottom">
                <p className="heroPanelNote">
                  Clean dashboard showing agent fleet overview, decision outcomes, task completion metrics, and a cost savings tracker.
                </p>
              </div>
            </div>
          </div>
        </section>

        <section className="section sectionLight">
          <div className="container">
            <h2 className="sectionTitle">Traditional staffing can&apos;t keep up with modern demands</h2>
            <div className="threeCol">
              <div className="infoCard">
                <h3 className="cardTitle">24/7 Coverage Gaps</h3>
                <p className="cardBody">Humans need sleep, breaks, and time off. Critical processes stall.</p>
              </div>
              <div className="infoCard">
                <h3 className="cardTitle">Scaling Costs</h3>
                <p className="cardBody">Hiring, training, and retaining talent at enterprise volume is expensive and slow.</p>
              </div>
              <div className="infoCard">
                <h3 className="cardTitle">Error &amp; Inconsistency</h3>
                <p className="cardBody">Human fatigue leads to mistakes, compliance risks, and variable output.</p>
              </div>
            </div>
          </div>
        </section>

        <SolutionSection />

        <section className="section sectionWhite" id="results">
          <div className="container">
            <h2 className="sectionTitle">Enterprises are already transforming</h2>

            <div className="testimonialGrid">
              <figure className="quoteCard">
                <blockquote>
                  “ClawStaffer replaced 40+ FTEs in our back-office processing. ROI in &lt;4 months.”
                </blockquote>
                <figcaption>VP Operations, Global Logistics Firm</figcaption>
              </figure>
              <figure className="quoteCard">
                <blockquote>
                  “We run customer support and data entry 24/7 with zero additional headcount.”
                </blockquote>
                <figcaption>CTO, Fortune 500 Financial Services</figcaption>
              </figure>
              <figure className="quoteCard">
                <blockquote>
                  “Security and compliance standards exceed our internal requirements.”
                </blockquote>
                <figcaption>CISO, Healthcare Enterprise</figcaption>
              </figure>
            </div>

            <div className="metricsBar" aria-label="Key metrics">
              <div className="metric">
                <div className="metricValue">Up to 85%</div>
                <div className="metricLabel">cost reduction in targeted roles</div>
              </div>
              <div className="metric">
                <div className="metricValue">99.9%</div>
                <div className="metricLabel">uptime across deployments</div>
              </div>
              <div className="metric">
                <div className="metricValue">4.2×</div>
                <div className="metricLabel">faster process completion</div>
              </div>
            </div>
          </div>
        </section>

        <section className="section sectionLight">
          <div className="container">
            <h2 className="sectionTitle">Deploy in weeks, not months</h2>
            <div className="steps">
              <div className="stepCard">
                <div className="stepIcon" aria-hidden="true">
                  <IconMap />
                </div>
                <h3 className="cardTitle">Discovery &amp; Mapping</h3>
                <p className="cardBody">We audit your processes and design agent workflows.</p>
              </div>
              <div className="stepCard">
                <div className="stepIcon" aria-hidden="true">
                  <IconWrench />
                </div>
                <h3 className="cardTitle">Custom Build &amp; Testing</h3>
                <p className="cardBody">Tailored agents trained on your data, rigorously tested in sandbox.</p>
              </div>
              <div className="stepCard">
                <div className="stepIcon" aria-hidden="true">
                  <IconRocket />
                </div>
                <h3 className="cardTitle">Live Deployment &amp; Optimization</h3>
                <p className="cardBody">Go live with full monitoring, continuous improvement.</p>
              </div>
            </div>
          </div>
        </section>

        <section className="section sectionDark">
          <div className="container">
            <h2 className="sectionTitle">Fits into your existing ecosystem</h2>
            <div className="integrationGrid" aria-label="Integrations">
              {[
                'Salesforce',
                'Workday',
                'SAP',
                'Oracle',
                'ServiceNow',
                'Microsoft Dynamics',
                'Slack',
                'Custom APIs',
              ].map((name) => (
                <div className="integrationLogo" key={name}>
                  {name}
                </div>
              ))}
            </div>
          </div>
        </section>

        <section className="finalCta" id="demo">
          <div className="container finalCtaInner">
            <div>
              <h2 className="finalTitle">Ready to build an always-on workforce?</h2>
              <p className="finalCopy">
                Enterprise plans include dedicated success team, custom deployment, and SLA-backed performance.
              </p>
            </div>
            <div className="finalButtons" role="group" aria-label="Final call to action">
              <button className="button buttonPrimary" onClick={openCalPopup}>
                Request Enterprise Demo <span aria-hidden="true">→</span>
              </button>
              <button className="button buttonSecondary" onClick={openCalPopup}>
                Schedule Call with Our Team
              </button>
            </div>
          </div>
        </section>
      </main>

      <footer className="footer">
        <div className="container footerInner">
          <div className="footerLeft">ClawStaffer © 2026</div>
          <div className="footerLinks">
            <a href="#security">Security &amp; Compliance</a>
            <a href="#results">Case Studies</a>
            <a href="#demo">Contact Sales</a>
            <a href="#privacy">Privacy Policy</a>
          </div>
        </div>
      </footer>

      <div id="privacy" />
    </>
  )
}

function SolutionSection() {
  const [active, setActive] = useState(0)

  const slides = [
    { title: 'Dashboard', caption: 'Monitor agent status, ownership, scenario routing, and queue health in real time.', image: '/screenshot-dashboard.png' },
    { title: 'Agents', caption: 'See why agents chose actions, when they escalated, and how exceptions were handled.', image: '/screenshot-agents.png' },
  ]

  return (
    <section className="section sectionDarkOrange">
      <div className="container">
        <h2 className="sectionTitle">Autonomous AI Agents That Never Stop</h2>

        <div className="featureGrid">
          <div className="featureCard">
            <div className="featureIcon" aria-hidden="true">
              <IconWorkflow />
            </div>
            <h3 className="cardTitle">Fully Autonomous Operation</h3>
            <p className="cardBody">
              Agents interpret context, make decisions based on scenarios, and execute complex workflows end-to-end without human intervention.
            </p>
          </div>
          <div className="featureCard">
            <div className="featureIcon" aria-hidden="true">
              <IconClock />
            </div>
            <h3 className="cardTitle">24/7 Availability</h3>
            <p className="cardBody">No downtime, no burnout, instant scaling across time zones.</p>
          </div>
          <div className="featureCard">
            <div className="featureIcon" aria-hidden="true">
              <IconShield />
            </div>
            <h3 className="cardTitle">Enterprise Security &amp; Compliance</h3>
            <p className="cardBody">SOC 2 Type II, GDPR, custom VPC deployment, audit trails.</p>
          </div>
          <div className="featureCard">
            <div className="featureIcon" aria-hidden="true">
              <IconPlug />
            </div>
            <h3 className="cardTitle">Seamless Integration</h3>
            <p className="cardBody">Connects to your existing stack: SAP, Salesforce, ServiceNow, custom APIs.</p>
          </div>
        </div>

        <div className="carousel" aria-label="Dashboard screenshots">
          <div className="carouselHeader">
            <div className="carouselTitle">
              <span className="carouselTitleAccent">Screenshot carousel:</span> {slides[active].title}
            </div>
            <div className="carouselControls" role="group" aria-label="Carousel controls">
              <button
                className="iconButton"
                type="button"
                onClick={() => setActive((i) => (i + slides.length - 1) % slides.length)}
                aria-label="Previous screenshot"
              >
                <IconChevronLeft />
              </button>
              <button
                className="iconButton"
                type="button"
                onClick={() => setActive((i) => (i + 1) % slides.length)}
                aria-label="Next screenshot"
              >
                <IconChevronRight />
              </button>
            </div>
          </div>

          <div className="carouselBody">
            <div className="screenshot">
              <div className="screenshotTop">
                {slides.map((s, idx) => (
                  <button
                    key={s.title}
                    className={idx === active ? 'screenshotPill screenshotPillActive' : 'screenshotPill'}
                    onClick={() => setActive(idx)}
                  >
                    {s.title}
                  </button>
                ))}
              </div>
              <div className="screenshotMain">
                {slides[active].image ? (
                  <img 
                    src={slides[active].image} 
                    alt={slides[active].title} 
                    className="screenshotImage"
                  />
                ) : (
                  <div className="screenshotPlaceholder">
                    <div className="screenshotPanelLarge" />
                    <div className="screenshotPanelRight">
                      <div className="screenshotPanelSmall" />
                      <div className="screenshotPanelSmall" />
                    </div>
                  </div>
                )}
              </div>
            </div>

            <p className="carouselCaption">{slides[active].caption}</p>

            <div className="carouselDots" role="tablist" aria-label="Carousel pages">
              {slides.map((s, idx) => (
                <button
                  className={idx === active ? 'dot dotActive' : 'dot'}
                  key={s.title}
                  type="button"
                  onClick={() => setActive(idx)}
                  aria-label={`Show ${s.title}`}
                  aria-selected={idx === active}
                  role="tab"
                />
              ))}
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}

function IconWorkflow() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path
        d="M7 7h10v10H7V7Zm-4 4h2v2H3v-2Zm16 0h2v2h-2v-2ZM11 3h2v2h-2V3Zm0 16h2v2h-2v-2Z"
        fill="currentColor"
      />
    </svg>
  )
}

function IconClock() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path
        d="M12 22a10 10 0 1 1 0-20 10 10 0 0 1 0 20Zm1-10.4 3.2 1.9-.8 1.3L11 12.2V6h2v5.6Z"
        fill="currentColor"
      />
    </svg>
  )
}

function IconShield() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path
        d="M12 2 20 6v6c0 5.1-3.4 9.7-8 10-4.6-.3-8-4.9-8-10V6l8-4Zm-1 12.6 6-6-1.4-1.4L11 11.8 8.4 9.2 7 10.6l4 4Z"
        fill="currentColor"
      />
    </svg>
  )
}

function IconPlug() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path
        d="M8 2h2v6h4V2h2v6h1a1 1 0 0 1 1 1v2a6 6 0 0 1-5 5.9V22h-2v-5.1A6 6 0 0 1 6 11V9a1 1 0 0 1 1-1h1V2Zm0 9a4 4 0 1 0 8 0v-1H8v1Z"
        fill="currentColor"
      />
    </svg>
  )
}

function IconMap() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path
        d="M9 4 3 6.5V20l6-2 6 2 6-2.5V4l-6 2-6-2Zm0 2.2 6 2V18l-6-2V6.2Zm-2 .2V16l-2 .7V7.2l2-.8Zm14 .8v9.7l-2 .8V8l2-.8Z"
        fill="currentColor"
      />
    </svg>
  )
}

function IconWrench() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path
        d="M21 7.6a5.5 5.5 0 0 1-7.3 5.2L7.3 19.2a2 2 0 0 1-2.8 0l-.7-.7a2 2 0 0 1 0-2.8l6.4-6.4A5.5 5.5 0 0 1 16.4 3l-2.7 2.7 1.8 1.8L18.2 4A5.5 5.5 0 0 1 21 7.6Z"
        fill="currentColor"
      />
    </svg>
  )
}

function IconRocket() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path
        d="M14 2c3.3 0 6 2.7 6 6 0 5.5-5 11-10.5 14l-3.2.7.7-3.2C10 14 15.5 9 15.5 3.5 15.5 2.7 14.8 2 14 2Zm3.2 7.3a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3ZM5.2 16.8 7.2 18.8 5 21H3v-2l2.2-2.2Z"
        fill="currentColor"
      />
    </svg>
  )
}

function IconChevronLeft() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M15.4 19 8.4 12l7-7 1.4 1.4L11.2 12l5.6 5.6L15.4 19Z" fill="currentColor" />
    </svg>
  )
}

function IconChevronRight() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M8.6 19 7.2 17.6 12.8 12 7.2 6.4 8.6 5l7 7-7 7Z" fill="currentColor" />
    </svg>
  )
}

function IconPlay() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M9 7.6v8.8L17 12 9 7.6Z" fill="currentColor" />
    </svg>
  )
}

export default App
