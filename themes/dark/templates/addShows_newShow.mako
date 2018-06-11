<%inherit file="/layouts/main.mako"/>
<%!
    import json

    from medusa import app
    from medusa.indexers.indexer_api import indexerApi
    from medusa.indexers.indexer_config import indexerConfig

    from six import iteritems, text_type
%>
<%block name="scripts">
<script type="text/javascript" src="js/add-show-options.js?${sbPID}"></script>
<script type="text/javascript" src="js/blackwhite.js?${sbPID}"></script>
## <script src="js/lib/frisbee@2.0.4.min.js"></script>
## <script src="js/lib/vue-frisbee.min.js"></script>
## <script src="js/vue-submit-form.js"></script>
<%
    valid_indexers = {
        '0': {
            'name': 'All Indexers'
        }
    }
    valid_indexers.update({
        text_type(indexer): {
            'name': config['name'],
            'showUrl': config['show_url'],
            'icon': config['icon'],
            'identifier': config['identifier']
        }
        for indexer, config in iteritems(indexerConfig)
        if config.get('enabled', None)
    })
%>
<script>
window.app = {};
const startVue = () => {
    window.app = new Vue({
        el: '#vue-wrap',
        metaInfo: {
            title: 'New Show'
        },
        data() {
            return {
                // @TODO: Fix Python conversions
                formwizard: null,
                otherShows: ${json.dumps(other_shows)},

                // Show Search
                searchStatus: '',
                firstSearch: false,
                searchResults: [],
                indexers: ${json.dumps(valid_indexers)},
                indexerTimeout: ${app.INDEXER_TIMEOUT},
                validLanguages: ${json.dumps(indexerApi().config['valid_languages'])},
                nameToSearch: ${json.dumps(default_show_name)},
                indexerId: ${provided_indexer or 0},
                indexerLanguage: ${json.dumps(app.INDEXER_DEFAULT_LANGUAGE)},
                currentSearch: {
                    cancel: null,
                    query: null,
                    indexerName: null,
                    languageName: null
                },

                // Provided info
                providedInfo: {
                    use: ${json.dumps(use_provided_info)},
                    seriesId: ${provided_indexer_id},
                    seriesName: ${json.dumps(provided_indexer_name)},
                    seriesDir: ${json.dumps(provided_show_dir)},
                    indexerId: ${provided_indexer},
                    indexerLanguage: 'en',
                },

                selectedRootDir: '',
                seriesIdentifier: ''
            };
        },
        mounted() {
            const init = () => {
                this.$watch('formwizard.currentsection', newValue => {
                    if (newValue === 0 && this.$refs.nameToSearch) {
                        this.$refs.nameToSearch.focus();
                    }
                });

                this.updateBlackWhiteList();
                const { providedInfo } = this;
                const { use, seriesId, seriesDir } = providedInfo;
                if (use && seriesId !== 0 && seriesDir) {
                    goToStep(3);
                }

                setTimeout(() => {
                    if (this.$refs.nameToSearch) {
                        this.$refs.nameToSearch.focus();

                        if (this.nameToSearch) {
                            this.searchIndexers();
                        }
                    }
                }, this.formwizard.setting.revealfx[1]);
            };

            /* JQuery Form to Form Wizard- (c) Dynamic Drive (www.dynamicdrive.com)
            *  This notice MUST stay intact for legal use
            *  Visit http://www.dynamicdrive.com/ for this script and 100s more. */
            // @TODO: we need to move to real forms instead of this

            const goToStep = num => {
                $('.step').each((idx, step) => {
                    if ($.data(step, 'section') + 1 === num) {
                        $(step).click();
                    }
                });
            }

            this.formwizard = new formtowizard({ // eslint-disable-line new-cap, no-undef
                formid: 'addShowForm',
                revealfx: ['slide', 300],
                oninit: init
            });

            $(document.body).on('change', 'select[name="quality_preset"]', () => {
                this.$nextTick(() => this.formwizard.loadsection(2));
            });

            $(document.body).on('change', '#anime', () => {
                this.updateBlackWhiteList();
                this.$nextTick(() => this.formwizard.loadsection(2));
            });
        },
        computed: {
            selectedSeries() {
                const { searchResults, seriesIdentifier } = this;
                if (searchResults.length === 0 || !seriesIdentifier) return null;
                return searchResults.find(s => s.identifier === seriesIdentifier);
            },
            showName() {
                const { providedInfo, selectedSeries } = this;
                // If we provided a show, use that
                if (providedInfo.use && providedInfo.seriesName) return providedInfo.seriesName;
                // If they've picked a radio button then use that
                if (selectedSeries !== null) return selectedSeries.seriesName;
                // Not selected / not searched
                return '';
            },
            addButtonDisabled() {
                const { seriesIdentifier, selectedRootDir, providedInfo } = this;
                if (providedInfo.use) return !providedInfo.seriesDir || providedInfo.seriesId === 0;
                return !selectedRootDir.length || seriesIdentifier === '';
            },
            spinnerSrc() {
                const themeSpinner = MEDUSA.config.themeSpinner;
                if (themeSpinner === undefined) return '';
                return 'images/loading32' + themeSpinner + '.gif';
            },
            showPath() {
                const { selectedRootDir, providedInfo, selectedSeries } = this;

                const pathSep = path => {
                    if (path.indexOf('\\') > -1) return '\\';
                    if (path.indexOf('/') > -1) return '/';
                    return '';
                };

                let showPath = 'unknown dir';
                // If we provided a show path, use that
                if (providedInfo.use && providedInfo.seriesDir) {
                    showPath = providedInfo.seriesDir;
                    const sepChar = pathSep(showPath);
                    if (showPath.slice(-1) !== sepChar) {
                        showPath += sepChar;
                    }
                // If we have a root dir selected, figure out the path
                } else if (selectedRootDir) {
                    showPath = selectedRootDir;
                    const sepChar = pathSep(showPath);
                    if (showPath.slice(-1) !== sepChar) {
                        showPath += sepChar;
                    }
                    // If we have a show selected, use the sanitized name
                    const dirName = selectedSeries ? selectedSeries.sanitizedName : '??';
                    showPath += '<i>' + dirName + '</i>' + sepChar;
                }
                return showPath;
            }
        },
        methods: {
            async submitForm(skipShow) {
                const { currentSearch, addButtonDisabled } = this;

                let formData;

                if (skipShow && skipShow === true) {
                    formData = new FormData();
                    formData.append('skipShow', 'true');

                    if (currentSearch.cancel) {
                        // Abort current search
                        currentSearch.cancel();
                        currentSearch.cancel = null;
                    }
                } else {
                    // If they haven't picked a show or a root dir don't let them submit
                    if (addButtonDisabled) {
                        this.$snotify.warning('You must choose a show and a parent folder to continue.');
                        return;
                    }

                    // Converts select boxes to command separated values [js/blackwhite.js]
                    generateBlackWhiteList(); // eslint-disable-line no-undef

                    formData = new FormData(this.$refs.addShowForm);
                }

                this.otherShows.forEach(nextShow => formData.append('other_shows', nextShow));

                const response = await apiRoute.post('addShows/addNewShow', formData);
                const { data } = response;
                const { result, message, redirect, params } = data;

                if (message) {
                    if (result === false) {
                        console.log('Error: ' + message);
                    } else {
                        console.log('Response: ' + message);
                    }
                }
                if (redirect) {
                    const baseUrl = apiRoute.defaults.baseURL;
                    if (params.length === 0) {
                        window.location.href = baseUrl + redirect;
                        return;
                    }

                    const form = document.createElement('form');
                    form.method = 'POST';
                    form.action = baseUrl + redirect;
                    form.acceptCharset = 'utf-8';

                    params.forEach(param => {
                        const element = document.createElement('input');
                        [ element.name, element.value ] = param; // Unpack
                        form.appendChild(element);
                    });

                    document.body.appendChild(form);
                    form.submit();
                }
            },
            rootDirsUpdated(rootDirs) {
                this.selectedRootDir = rootDirs.length === 0 ? '' : rootDirs.find(rd => rd.selected).path;
            },
            async searchIndexers() {
                let { currentSearch, nameToSearch, indexerLanguage, indexerId, indexerTimeout, indexers } = this;

                if (!nameToSearch) return;

                // Get the language name
                const indexerLanguageSelect = this.$refs.indexerLanguage.$el;
                const indexerLanguageName = indexerLanguageSelect[indexerLanguageSelect.selectedIndex].text;

                const indexerName = indexers[indexerId].name;

                if (currentSearch.cancel) {
                    // If a search is currently running, and the new search is the same, don't start a new search
                    const sameQuery = nameToSearch === currentSearch.query;
                    const sameIndexer = indexerName == currentSearch.indexerName;
                    const sameLanguage = indexerLanguageName === currentSearch.languageName;
                    if (sameQuery && sameIndexer && sameLanguage) {
                        return;
                    }
                    // Abort search before starting a new one
                    currentSearch.cancel();
                    currentSearch.cancel = null;
                }

                currentSearch.query = nameToSearch;
                currentSearch.indexerName = indexerName;
                currentSearch.languageName = indexerLanguageName;

                this.seriesIdentifier = '';
                this.searchResults = [];

                const config = {
                    params: {
                        query: nameToSearch,
                        indexerId: indexerId,
                        language: indexerLanguage
                    },
                    timeout: indexerTimeout * 1000,
                    // An executor function receives a cancel function as a parameter
                    cancelToken: new axios.CancelToken(cancel => currentSearch.cancel = cancel)
                };

                this.$nextTick(() => this.formwizard.loadsection(0)); // eslint-disable-line no-use-before-define

                let data = null;
                try {
                    const response = await api.get('internal/searchIndexersForShowName', config);
                    data = response.data;
                }
                catch (error) {
                    if (axios.isCancel(error)) {
                        // Request cancelled
                        return;
                    }
                    if (error.code === 'ECONNABORTED') {
                        // Request timed out
                        this.searchStatus = 'Search timed out, try again or try another indexer';
                        return;
                    }
                    // Request failed
                    this.searchStatus = 'Search failed with error: ' + error;
                    return;
                }
                finally {
                    currentSearch.cancel = null;
                }

                if (!data) return;

                const { languageId } = data;
                this.searchResults = data.results
                    .map(result => {
                        // Compute whichSeries value (without the last item - sanitizedName)
                        whichSeries = result.slice(0, -1).join('|');

                        // Unpack result items 0 through 7 (Array)
                        let [
                            indexerName,
                            indexerId,
                            indexerShowUrl,
                            seriesId,
                            seriesName,
                            premiereDate,
                            network,
                            sanitizedName
                        ] = result;

                        identifier = [indexers[indexerId].identifier, seriesId].join('')

                        // Append seriesId to indexer show url
                        indexerShowUrl += seriesId;
                        // For now only add the languageId id to the tvdb url, as the others might have different routes.
                        if (languageId && languageId !== '' && indexerId === 1) {
                            indexerShowUrl += '&lid=' + languageId
                        }

                        // Discard 'N/A' and '1900-01-01'
                        const filter = string => ['N/A', '1900-01-01'].includes(string) ? '' : string;
                        premiereDate = filter(premiereDate);
                        network = filter(network);

                        indexerIcon = 'images/' + indexers[indexerId].icon;

                        return {
                            identifier,
                            whichSeries,
                            indexerName,
                            indexerId,
                            indexerShowUrl,
                            indexerIcon,
                            seriesId,
                            seriesName,
                            premiereDate,
                            network,
                            sanitizedName
                        };
                    });

                if (this.searchResults.length !== 0) {
                    // Select the first result
                    this.seriesIdentifier = this.searchResults[0].identifier;
                }

                this.searchStatus = '';
                this.firstSearch = true;

                this.$nextTick(() => {
                    this.formwizard.loadsection(0); // eslint-disable-line no-use-before-define
                });
            },
            updateBlackWhiteList() {
                // Currently requires jQuery
                if ($ === undefined) return;
                $.updateBlackWhiteList(this.showName);
            }
        }
    });
};
</script>
</%block>
<%block name="content">
<vue-snotify></vue-snotify>
<h1 class="header">New Show</h1>
<div class="newShowPortal">
    <div id="config-components">
        <ul><li><app-link href="#core-component-group1">Add New Show</app-link></li></ul>
        <div id="core-component-group1" class="tab-pane active component-group">
            <div id="displayText">Adding show <b v-html="showName"></b> into <b v-html="showPath"></b></div>
            <br />
            <form id="addShowForm" ref="addShowForm" method="post" action="addShows/addNewShow" accept-charset="utf-8">
                <fieldset class="sectionwrap">
                    <legend class="legendStep">Find a show on selected indexer(s)</legend>
                    <div v-if="providedInfo.use" class="stepDiv">
                        Show retrieved from existing metadata:
                        <span v-if="providedInfo.indexerId !== 0 && providedInfo.seriesId !== 0">
                            <app-link :href="indexers[providedInfo.indexerId].showUrl + providedInfo.seriesId.toString()">
                                <b>{{ providedInfo.seriesName }}</b>
                            </app-link>
                            <br />
                            Show indexer:
                            <b>{{ indexers[providedInfo.indexerId].name }}</b>
                            <img height="16" width="16" :src="'images/' + indexers[providedInfo.indexerId].icon" />
                        </span>
                        <span v-else>
                            <b>{{ providedInfo.seriesName }}</b>
                        </span>
                        <input type="hidden" name="indexer_lang" :value="providedInfo.indexerLanguage" />
                        <input type="hidden" name="whichSeries" :value="providedInfo.seriesId" />
                        <input type="hidden" name="providedIndexer" :value="providedInfo.indexerId" />
                    </div>
                    <div v-else class="stepDiv">
                        <input type="text" v-model.trim="nameToSearch" ref="nameToSearch" @keyup.enter="searchIndexers" class="form-control form-control-inline input-sm input350"/>
                        &nbsp;&nbsp;
                        <language-select @update-language="indexerLanguage = $event" ref="indexerLanguage" name="indexer_lang" :language="indexerLanguage" :available="validLanguages.join(',')" class="form-control form-control-inline input-sm"></language-select>
                        <b>*</b>
                        &nbsp;
                        <select name="providedIndexer" v-model.number="indexerId" class="form-control form-control-inline input-sm">
                            <option v-for="(indexer, indexerId) in indexers" :value="indexerId">{{indexer.name}}</option>
                        </select>
                        &nbsp;
                        <input class="btn-medusa btn-inline" type="button" value="Search" @click="searchIndexers" />

                        <p style="padding: 20px 0;">
                            <b>*</b> This will only affect the language of the retrieved metadata file contents and episode filenames.<br />
                            This <b>DOES NOT</b> allow Medusa to download non-english TV episodes!
                        </p>

                        <div v-if="currentSearch.cancel !== null">
                            <img :src="spinnerSrc" height="32" width="32" />
                            Searching <b>{{ currentSearch.query }}</b>
                            on {{ currentSearch.indexerName }}
                            in {{ currentSearch.languageName }}...
                        </div>
                        <div v-else-if="!firstSearch || searchStatus !== ''" v-html="searchStatus"></div>
                        <div v-else class="search-results">
                            <legend class="legendStep">Search Results:</legend>
                            <table v-if="searchResults.length !== 0" class="search-results">
                                <thead>
                                    <tr>
                                        ## @TODO: Remove the need for the whichSeries value
                                        <th><input v-if="selectedSeries !== null" type="hidden" name="whichSeries" :value="selectedSeries.whichSeries" /></th>
                                        <th>Show Name</th>
                                        <th class="premiere">Premiere</th>
                                        <th class="network">Network</th>
                                        <th class="indexer">Indexer</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <tr v-for="result in searchResults" @click="seriesIdentifier = result.identifier" :class="{ selected: seriesIdentifier === result.identifier }">
                                        <td style="text-align: center; vertical-align: middle;">
                                            <input v-model="seriesIdentifier" type="radio" :value="result.identifier" />
                                        </td>
                                        <td>
                                            <app-link :href="result.indexerShowUrl" title="Go to the show's page on the indexer site">
                                                <b>{{ result.seriesName }}</b>
                                            </app-link>
                                        </td>
                                        <td class="premiere">{{ result.premiereDate }}</td>
                                        <td class="network">{{ result.network }}</td>
                                        <td class="indexer">
                                            {{ result.indexerName }}
                                            <img height="16" width="16" :src="result.indexerIcon" />
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            <div v-else class="no-results">
                                <b>No results found, try a different search.</b>
                            </div>
                        </div>
                    </div>
                </fieldset>
                <fieldset class="sectionwrap">
                    <legend class="legendStep">Pick the parent folder</legend>
                    <div v-if="providedInfo.use && providedInfo.seriesDir" class="stepDiv">
                        Pre-chosen Destination Folder: <b>{{ providedInfo.seriesDir }}</b><br />
                        <input type="hidden" name="fullShowPath" :value="providedInfo.seriesDir" /><br />
                    </div>
                    <div v-else class="stepDiv">
                        <root-dirs @update:root-dirs="rootDirsUpdated"></root-dirs>
                    </div>
                </fieldset>
                <fieldset class="sectionwrap">
                    <legend class="legendStep">Customize options</legend>
                    <div class="stepDiv">
                        <%include file="/inc_addShowOptions.mako"/>
                    </div>
                </fieldset>
            </form>
            <br />
            <div style="width: 100%; text-align: center;">
                <input @click.prevent="submitForm" class="btn-medusa" type="button" value="Add Show" :disabled="addButtonDisabled" />
                <input v-if="otherShows.length !== 0" @click.prevent="submitForm(true);" class="btn-medusa" type="button" value="Skip Show" />
                <p v-if="otherShows.length !== 0"><i>({{ otherShows.length }} more {{ otherShows.length > 1 ? 'shows' : 'show' }} left)</i></p>
            </div>
        </div>
    </div>
</div>
</%block>
