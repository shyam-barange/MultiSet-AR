# Multiset AR Engine - iOS App Documentation
## Complete Platform Overview & Capabilities

---

## 1. PRODUCT OVERVIEW

### What is MultiSet AI?
MultiSet AI is the **independent spatial infrastructure layer for Physical AI**. We provide human and machine-readable maps for the physical world, enabling every device with a camera to understand exactly where it is and maintain that understanding over time.

**Core Mission:** Bridge the gap between the physical and digital worlds by providing spatial ground truth infrastructure that powers AR, robotics, and autonomous systems.

**Key Distinction:** MultiSet is the only **independent** VPS provider - not owned by a reality capture company, device maker, or cloud vendor. This means unbiased, vendor-agnostic solutions focused solely on spatial intelligence.

---

## 2. CORE TECHNOLOGY PILLARS

### 2.1 Visual Positioning System (VPS)
**Spatial Ground Truth Infrastructure**
- Enables every camera-equipped device to know exactly where it is with centimeter-level accuracy
- Provides instant 6-Degree-of-Freedom (6-DoF) relocalization
- Maintains persistent spatial understanding across time and environmental changes

**Technical Achievements:**
- **≤5 cm accuracy** with minimal drift
- Instant re-localization in challenging conditions:
  - Low light environments
  - High-glare situations
  - Occlusion scenarios
  - Complex motion patterns
  - Severe weather conditions

### 2.2 Object Tracking
Real-time tracking and identification of physical objects within mapped environments

### 2.3 3D Mapping
**Scan-Agnostic Mapping Pipeline**
- Process data from ANY source without proprietary lock-in
- Supported input formats:
  - LiDAR point clouds
  - E57 files (3D scanning standard)
  - Gaussian Splats (3DGS)
  - 360-degree video
  - Textured 3D meshes
  - iPhone scans
  - Drone captures
  - Any camera-based reality capture

**Key Advantage:** No re-scanning required when changing data sources or formats

### 2.4 Additional Platform Features
- **Map Versioning:** Control and manage multiple versions of spatial maps
- **E57 to VPS:** Convert point cloud data directly
- **3DGS to VPS:** Integrate Gaussian splat technology
- **360 to VPS:** Process 360-degree imagery

---

## 3. DEPLOYMENT ARCHITECTURE

### 3.1 Cloud Deployment Options (Choose Your Model)

#### Managed Cloud
- **Best for:** Fast time-to-value, minimal operational overhead
- Fully managed infrastructure with automatic scaling
- SOC 2 & ISO 27001 certified
- Fastest deployment path
- MultiSet handles all maintenance and updates

#### Enterprise Private Cloud
- **Best for:** Regulated industries, data sovereignty requirements
- Your security perimeter with MultiSet management
- Full control over infrastructure location
- Maintains compliance with regional data laws
- Hybrid approach: security + convenience

#### On-Device (Offline)
- **Best for:** Air-gapped systems, no network availability
- Completely offline operation for regulated industries
- Full control and privacy
- No network connectivity required
- Perfect for sensitive manufacturing and government use cases

**Flexibility:** Choose your deployment model based on your security, compliance, and operational requirements. Switch models as your needs evolve.

---

## 4. PLATFORM CAPABILITIES & COMPETITIVE ADVANTAGES

### 4.1 Robustness & Accuracy
**MultiSet Advantage:** Industry-leading stability even in harsh conditions

| Feature | MultiSet | Competitors |
|---------|----------|-------------|
| **Accuracy & Drift** | ≤5 cm accuracy, low drift; instant 6-DoF relocalization in challenging conditions | Drops or drifts under glare, low light, or occlusion; slower re-locks |
| **Light & Weather Resilience** | Robust in tough light, weather, and challenging motion | Struggles with low light, glare, occlusion |

### 4.2 Scan-Agnostic Input Processing
**MultiSet Advantage:** Use data from any source, no vendor lock-in

| Feature | MultiSet | Competitors |
|---------|----------|-------------|
| **Input Flexibility** | LiDAR, E57, point clouds, textured meshes, Gaussian splats, 360 video, iPhone scans | Pre-mapping lock-in to vendor app or limited file formats |
| **Format Support** | Any reality capture modality | Proprietary formats only |

### 4.3 Multi-Floor Persistence
**MultiSet Advantage:** Enterprise-grade scalability across entire facilities

| Feature | MultiSet | Competitors |
|---------|----------|-------------|
| **Scaling** | Plant-wide continuity - auto-stitches floors/buildings; safe re-maps keep anchors/semantics intact | Manual linking; updates can break anchors and content |
| **Map Updates** | Non-destructive re-mapping preserves all AR content and semantic data | Updates often require full re-mapping |

### 4.4 Dynamic Environment Tolerance
**MultiSet Advantage:** Maintains accuracy as physical world changes

| Feature | MultiSet | Competitors |
|---------|----------|-------------|
| **Adaptability** | Change-tolerant - stays stable as equipment or layouts move; minimal re-scans required | Static-scene bias; frequent re-mapping needed to maintain accuracy |
| **Operational Cost** | Significantly reduced re-mapping frequency | High ongoing mapping costs |

### 4.5 Indoor ↔ Outdoor Seamless Transitions
**MultiSet Advantage:** Unified positioning across all environments

| Feature | MultiSet | Competitors |
|---------|----------|-------------|
| **Hybrid Positioning** | Seamless handover - top indoor performance with clean transitions to GNSS/RTK, IoT, UWB | Outdoor-first stacks struggle indoors and at transitions |
| **Integration** | Works with GPS, RTK, UWB, and IoT sensors | Limited outdoor integration |

### 4.6 Deployment Flexibility
**MultiSet Advantage:** True choice and data ownership

| Feature | MultiSet | Competitors |
|---------|----------|-------------|
| **Infrastructure** | Your cloud or ours - public, private, on-prem, or on-device/offline; full data ownership | Vendor-cloud default; limited offline/on-prem options |
| **Data Control** | Complete data ownership and control | Data lives in vendor's ecosystem |

### 4.7 Enterprise Support
**MultiSet Advantage:** Engineer-led support with SLAs

| Feature | MultiSet | Competitors |
|---------|----------|-------------|
| **Support Model** | 24/7 engineer-led SLAs; comprehensive SDKs | Support varies; forum-first or business-hours only |
| **SDK Coverage** | SDKs for Unity, iOS, Android, WebXR, Quest, ROS2 | Narrower SDK coverage |

---

## 5. MULTISET SDK & PLATFORM SUPPORT

### 5.1 Comprehensive Platform Coverage
One unified SDK deployed across multiple platforms and devices:

**Platforms Supported:**
- **iOS** - Native iOS applications and AR experiences
- **Android** - Full Android platform support
- **Web** - WebXR and browser-based AR
- **Unity** - Game engines and cross-platform development
- **Meta Quest** - VR/MR headset deployment
- **ROS2** - Robotics and autonomous systems

### 5.2 Target Devices
- Mobile phones and tablets (iPhone, iPad, Android devices)
- AR/VR headsets (Meta Quest, Apple Vision Pro)
- Smart glasses and AR wearables
- Robotics systems (AMRs, drones, cobots)
- Industrial and enterprise devices

---

## 6. KEY USE CASES

### 6.1 Front Line Operations - AR Work Instructions & Asset Navigation
**Industry:** Manufacturing, Field Service, Maintenance

**Value Proposition:**
- Guided AR workflows with step-by-step visual instructions
- Asset location and navigation within complex facilities
- Reduced worker training time
- Improved first-time-right accuracy

**Typical Applications:**
- Equipment assembly and installation
- Maintenance procedures
- Inspection workflows
- Asset location and tracking
- Safety compliance verification

**Expected Outcomes:**
- 30-50% reduction in training time
- Improved accuracy and consistency
- Reduced error rates and rework
- Faster time-to-productivity for new workers

---

### 6.2 Human-Robot Ground Truth for AMRs, Drones & Cobots
**Industry:** Robotics, Manufacturing, Logistics, Warehouse Automation

**Value Proposition:**
- Provide robots and autonomous systems with accurate spatial awareness
- Enable safe, efficient autonomous operation in shared spaces
- Real-time localization and mapping for autonomous vehicles

**Technical Applications:**
- Autonomous Mobile Robot (AMR) navigation
- Drone flight operations
- Collaborative robot (Cobot) positioning
- Warehouse automation and optimization
- Last-mile delivery systems

**Expected Outcomes:**
- Improved robot accuracy and reliability
- Safer human-robot collaboration
- Increased operational efficiency
- Reduced dependence on infrastructure markers (QR codes, beacons)

---

### 6.3 AR QA & Commissioning for Construction & Infrastructure
**Industry:** Construction, Infrastructure, Utilities, Real Estate

**Value Proposition:**
- AR-assisted quality assurance processes
- Digital commissioning documentation
- Construction progress verification
- Building systems commissioning

**Applications:**
- Construction QA and verification
- Building systems commissioning
- Infrastructure inspection and documentation
- Punch-list management
- As-built documentation
- MEP (Mechanical, Electrical, Plumbing) verification

**Expected Outcomes:**
- Faster construction commissioning
- Improved documentation accuracy
- Reduced rework and punch-list items
- Better stakeholder visibility

---

### 6.4 Retail Planogram Compliance & Spatial Commerce
**Industry:** Retail, Consumer Goods, Logistics

**Value Proposition:**
- Verify product placement against planograms
- Enable immersive shopping experiences
- Optimize retail shelf management
- Enable location-based commerce

**Applications:**
- Shelf compliance verification
- Product placement optimization
- In-store navigation and wayfinding
- Location-based promotions and offers
- Inventory location tracking
- Immersive product visualization

**Expected Outcomes:**
- Improved brand compliance
- Optimized product sales
- Enhanced customer experience
- Faster compliance audits

---

## 7. RECOGNITION & MARKET VALIDATION

### 7.1 Industry Awards
- **Auggie Awards 2026:** Best Developer Tool Award
- Recognition for innovation and developer experience

### 7.2 Enterprise Validation
- **AREA Research Report (2025):** Rated "Most Robust Visual Positioning System"
- Independent third-party validation of technical capabilities
- 15th Annual AREAResearch Report from the Augmented Reality Enterprise Alliance

### 7.3 Customer Trust
**Enterprise Customers Include:**
- Bosch (Industrial automation & IoT)
- AstraZeneca (Pharmaceutical & Life Sciences)
- Spotify (Digital innovation)
- Nivesha Ventures (Investment & Tech Infrastructure)
- Treedis (Environmental Solutions)
- And many more Fortune 500 and innovative enterprises

---

## 8. IMPLEMENTATION & DEPLOYMENT TIMELINE

### 8.1 Quick Start (Days 1-7)
- **Prototype Development:** Stand up localized AR experiences in minutes using SDK samples
- **Initial Integration:** Connect to your first spatial data source
- **Proof of Concept:** Validate core use case with real data

### 8.2 Pilot Phase (Weeks 2-4)
- **Expanded Coverage:** Extend mapping to pilot area (floor, building section)
- **Integration Testing:** Test with your existing systems and devices
- **Performance Validation:** Measure accuracy and reliability metrics
- **Team Training:** Get your team up to speed on SDK and operations

### 8.3 Expansion Phase (Month 2)
- **Scaling Up:** Expand to full facility or campus by stitching maps
- **Process Optimization:** Integrate into existing workflows and operational processes
- **Content Creation:** Build full set of AR content and instructions

### 8.4 Production (Month 3+)
- **Full Deployment:** Organization-wide rollout
- **Optimization:** Fine-tune based on real-world usage patterns
- **Continuous Improvement:** Regular map updates and content enhancement

### 8.5 Expected 90-Day Outcomes
**Common Early Wins:**
- Guided AR workflows in production
- Wayfinding and navigation enabled
- Faster operator training
- AR-assisted inspection workflows
- Measurable productivity improvements
- Improved accuracy and compliance

---

## 9. PRICING & COMMERCIAL MODEL

### 9.1 Getting Started
**Free Tier Available:**
- Prototype and validate your use case at no cost
- Full SDK access for development
- Limited cloud usage for testing

**Production Pricing:**
Based on transparent usage metrics:
- Number and size of maps deployed
- API calls and usage volume
- Active map updates
- Concurrent users/devices

**Flexibility:**
- Pay-as-you-grow pricing model
- No long-term contracts required
- Scale up or down based on needs
- Volume discounts available

**Deployment Cost:** Varies based on deployment model chosen (managed cloud, private, on-device)

---

## 10. TECHNICAL INTEGRATION DETAILS

### 10.1 SDK Integration
**For iOS Development:**
- Native iOS SDK with full Swift/Objective-C support
- Easy integration into existing iOS apps
- Minimal performance overhead
- Complete ARKit integration where applicable
- Background positioning support

**API Access:**
- REST API for backend integration
- Real-time positioning endpoints
- Map management APIs
- Content synchronization
- Comprehensive API documentation

### 10.2 Data Privacy & Security
- **SOC 2 Type II Certified**
- **ISO 27001 Certified**
- End-to-end encryption options
- GDPR compliant
- HIPAA-ready deployments
- Industry-specific compliance certifications

### 10.3 Performance Specifications
- **Positioning Accuracy:** ±5 cm in most conditions
- **Update Frequency:** Up to 60 Hz for real-time applications
- **Re-localization Time:** <100ms in most scenarios
- **Drift Rate:** <0.1% per minute in typical conditions
- **Battery Impact:** Minimal impact on device battery life

---

## 11. COMPETITIVE POSITIONING

### How MultiSet Differs from Alternatives

**vs. Vuforia:**
- Independent provider (not owned by device/camera company)
- Better robustness in challenging light conditions
- Scan-agnostic input (Vuforia requires specific formats)
- Better support for multi-floor facilities
- More flexible deployment options

**vs. Azure Spatial Anchors:**
- Independent provider (not cloud-vendor lock-in)
- Better outdoor-to-indoor transitions
- Superior dynamic environment support
- Full offline capability
- On-device deployment options

**vs. Generic AR Frameworks:**
- Purpose-built for enterprise spatial intelligence
- 10x better accuracy than general AR toolkits
- Designed for industrial and enterprise scale
- Dedicated support and SLAs
- Built-in multi-facility management

---

## 12. GETTING STARTED WITH MULTISET AR ENGINE

### 12.1 For Developers
**Free Resources:**
- SDK downloads and documentation
- Code samples and tutorials
- Community Discord channel
- Technical documentation portal
- Developer dashboard for API management

**Website:** https://developer.multiset.ai/

### 12.2 For Enterprise
**Evaluation Path:**
1. **Request Demo:** Connect with MultiSet sales team
   - Understand your specific use case
   - Discuss deployment requirements
   - Review relevant case studies

2. **Pilot Program:** 
   - 90-day evaluation period
   - Dedicated technical support
   - Hands-on implementation assistance
   - Success metrics and KPI definition

3. **Production Deployment:**
   - Structured rollout plan
   - Ongoing engineering support
   - 24/7 SLA support
   - Continuous optimization

**Contact:** contact@multiset.ai

### 12.3 Documentation & Community
- **Official Docs:** https://docs.multiset.ai
- **System Status:** https://status.multiset.ai/
- **Community Discord:** discord.com/invite/pftwqThTxb
- **GitHub:** github.com/MultiSet-AI
- **YouTube:** @MultiSetAI
- **LinkedIn:** linkedin.com/company/multiset-ai
- **Instagram:** instagram.com/multiset.ai/
- **Twitter/X:** @multiset_ai

---

## 13. APP FEATURE RECOMMENDATIONS FOR MULTISET AR ENGINE iOS

Based on MultiSet's capabilities, consider including in your iOS app:

### 13.1 Core Features
- **Real-time Positioning** - Show user's precise location within mapped environments
- **AR Navigation** - Visual pathfinding and wayfinding
- **Work Instructions** - Step-by-step guided workflows with AR overlays
- **Asset Tracking** - Locate and identify physical objects
- **Map Viewer** - Browse 3D maps of facilities
- **Offline Mode** - Full functionality without network

### 13.2 Enterprise Features
- **Multi-site Support** - Switch between different facility maps
- **Role-based Access** - Different capabilities for different user roles
- **Audit Logging** - Track all user actions for compliance
- **Integration APIs** - Connect to backend systems
- **Analytics Dashboard** - Usage metrics and insights
- **Offline Sync** - Automatic updates when connected

### 13.3 User Interface Elements
- **Live AR View** - Real-time camera feed with AR overlays
- **Map Selector** - Browse available facilities and maps
- **Search & Filters** - Find locations and assets quickly
- **Bookmarks** - Save frequently visited locations
- **Notifications** - Real-time alerts and instructions
- **Settings** - Customization and preferences

---

## 14. COMPANY INFORMATION

**MultiSet AI Inc.**

**Headquarters:**
28 Geary Street, Suite #371
San Francisco, California 94108, USA

**Contact Email:** contact@multiset.ai

**Founded:** 2024 (Industry launched with strong backing and team from spatial computing leaders)

**Vision:** Build the independent infrastructure layer that powers the next era of physical AI applications

---

## APPENDIX: KEY STATISTICS

- **Positioning Accuracy:** ≤5 cm
- **Supported Platforms:** 6 (iOS, Android, Web, Unity, Quest, ROS2)
- **Deployment Models:** 3 (Cloud, Private, On-Device)
- **Primary Use Cases:** 4 major verticals covered
- **Enterprise Customers:** Fortune 500 and innovative startups
- **SDK Languages:** Swift, Kotlin, JavaScript, C++, Python
- **Support Model:** 24/7 Engineer-led SLAs
- **Certifications:** SOC 2 Type II, ISO 27001
- **Industry Recognition:** Best Developer Tool (Auggie Awards 2026), Most Robust VPS (AREA 2025)

---

## DOCUMENT INFORMATION

**Created For:** Multiset AR Engine - iOS Application Development
**Document Type:** Product Overview & Technical Specification
**Version:** 1.0
**Last Updated:** August 2026
**Content Source:** MultiSet AI Official Website (multiset.ai)

---

*This document is designed to serve as a comprehensive reference for developing the Multiset AR Engine iOS application, highlighting all key capabilities, use cases, and technical specifications available from the MultiSet platform.*